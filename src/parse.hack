namespace toml;

require_once __DIR__."/../vendor/hh_autoload.hh";

use \LogicException;
use \HH\Lib\Str;

enum tokenType : int { 
	BARE_KEY 			= 0;
	STRING 				= 1;
	STRING_MULTILINE	= 2;

	INTEGER				= 10;
	FLOAT 				= 11;
	BOOL 				= 12;
	DATETIME			= 13;

	OP_EQUALS 			= 20;
	OP_DOT 				= 21;

	OP_BRACKET_OPEN		= 30;
	OP_BACKET_CLOSE 	= 31;
	OP_DB_BRACKET_OPEN	= 32;
	OP_DB_BRACKET_CLOSE	= 33;

	OP_BRACE_OPEN 		= 35;
	OP_BRACE_CLOSE 		= 36;

	EOL 				= 50;
	EOF 				= 51;
}

class token { 

	public function toString() : string { 
		return \sprintf("(%s,%s)\t%d\t:%s", $this->line, $this->col, $this->type, $this->text);
	}

	private int $line;
	private int $col;
	private string $text;
	private tokenType $type;

	public function getLine() : int { return $this->line; }
	public function getCol() : int { return $this->col; }
	public function getText() : string { return $this->text; }
	public function getType() : tokenType { return $this->type; }


	public function setLine(int $line) : void { $this->line = $line; }
	public function setCol(int $col) : void { $this->col = $col; }
	public function setText(string $text) : void { $this->text = $text; }
	public function setType(tokenType $type) : void { $this->type = $type; }

	public function __construct(tokenType $type, int $line, int $col, string $text = ''){
		$this->line = $line;
		$this->col = $col;
		$this->text = $text;
		$this->type = $type;
	}

	public function isKey(): bool { return ($this->type == tokenType::BARE_KEY || $this->type == tokenType::STRING); }
	public function isString() : bool { return ($this->type == tokenType::STRING || $this->type == tokenType::STRING_MULTILINE); }
	public function isValue() : bool { 
		switch($this->type) {
			case tokenType::STRING:
			case tokenType::STRING_MULTILINE:
			case tokenType::INTEGER:
			case tokenType::FLOAT:
			case tokenType::BOOL:
			case tokenType::DATETIME:
				return true;
			default:
				return false; 
		}
	}
	public function isEndAnchor() : bool { return ($this->type == tokenType::EOL) || ($this->type == tokenType::EOF); }

	public function value() : mixed { 
		if(! $this->isValue()) throw new LogicException("This token is not a value type");
		if($this->isString()) return $this->text; 

		switch($this->type) {
			case tokenType::INTEGER: 		return \intval($this->text);
			case tokenType::FLOAT: 			return \doubleval($this->text);

			case tokenType::BOOL:
				if($this->text === "true") return TRUE;
				else return FALSE;

			case tokenType::DATETIME:		return new \DateTime($this->text);

			default:						throw new LogicException("Type not handled in value()");
		}
	}
}


class TOMLException extends \Exception { }

abstract class lexframe { 

	protected Decoder $parent;
	protected position $position; // line, col 

	public function __construct(Decoder $parent, ?string $char = NULL) { 
		$this->parent = $parent;
		$this->position = $parent->getPosition();

		if($char != NULL) $this->lexc($char); 
	}

	/**
	 * Process the current character $char.  Return $this to keep current frame, nonnull to replace, null to pop 
	 */
	abstract public function lexc(string $char) : lexframe;

	/**
	 * Call this once the current token ends 
	 */
	abstract public function finalize() : void;

	protected string $value = "";

	protected function addToken(tokenType $type) : void {
		$this->parent->addToken($type, $this->position, $this->value);  
	}

}

class lexerRoot extends lexframe { 

	private bool $isBareKey = false; 
	private bool $isOperator = false; 

	public function lexc(string $char) : lexframe {

		// DEBUG
		\printf("> ROOT:\t\t[%s] %s :%s\n", $char, ($this->isBareKey ? 'b' : '-').($this->isOperator ? 'o' : '-'), $this->value);

		// Whitespace - end current token if necessary 
		if($this->parent->handleSpace($char)) { 
			if(Str\length($this->value) == 0) return $this; 
			else return new lexerRoot($this->parent); 
		}

		// See if the character could belong to an unquoted "bare" key 
		if(\preg_match("([a-zA-Z0-9]|-|_)", $char)) 
		{ 	
			if($this->isOperator) return new lexerRoot($this->parent, $char); // Was previously an operator - jump out
			$this->isBareKey = TRUE; 

			$this->value .= $char;
			return $this; 

		}
		else 
		{
			if($this->isBareKey) return new lexerRoot($this->parent, $char); // Was previously a key - jump out 
			$this->isOperator = TRUE; 

			switch($char) { 

	 			// Single character operators
				case '=':
				case '.':
				case '{':
				case '}':
									$this->value = $char; 
									return new lexerRoot($this->parent); 

				// Brackets, which can be doubled 

				case '[':
				case ']':

					// Has no lookbehind
					if(Str\length($this->value) == 0) { 
						$this->isOperator = TRUE; 
						$this->value .= $char; 
						return $this; 
					}

					else { 

						// It is a double bracket 
						if($char == $this->value) 	return new lexerRoot($this->parent); 

						// Nope, process them separately 
						else 						return new lexerRoot($this->parent, $char); 
					}

				// Other lexer frames 

				// Begin a comment
				case '#':			return new lexerComment($this->parent);
				// Begin a string
				case "'":
				case '"':
									return new lexerString($this->parent, $char);

				default: 
					$this->value .= $char;
					throw new TOMLException("Unrecognized token \"".$this->value."\" at (".$this->position[0].','.$this->position[1].')');
			}	 
		}
	}

	public function finalize() : void { 
		if(Str\length($this->value) == 0) return; // Ignore empty tokens

		if($this->isBareKey) {
			switch($this->value) { 
				case 'true':
				case 'false':
							$this->addToken(tokenType::BOOL); 					return; 
				default:	$this->addToken(tokenType::BARE_KEY); 				return;
			}
		}

		else switch($this->value) { 

				case '=': 	$this->addToken(tokenType::OP_EQUALS);				return;
				case '.': 	$this->addToken(tokenType::OP_DOT);					return;
				case '{': 	$this->addToken(tokenType::OP_BRACE_OPEN);			return;
				case '}':	$this->addToken(tokenType::OP_BRACE_CLOSE);			return;
				case '[': 	$this->addToken(tokenType::OP_BRACKET_OPEN);		return;
				case ']': 	$this->addToken(tokenType::OP_DB_BRACKET_CLOSE);	return;
				case '[[': 	$this->addToken(tokenType::OP_DB_BRACKET_OPEN);		return;
				case ']]': 	$this->addToken(tokenType::OP_DB_BRACKET_CLOSE);	return;

				default: 	throw new LogicException("Unhandled token type in root lexer: \"".$this->value."\"");
			}

	}

}

//
// Comments
//

class lexerComment extends lexframe { 

	public function lexc(string $char) : lexframe {
		// read until newline, then pop 
		$this->parent->handleSpace($char); 
		return ($char == '\n' ? new lexerRoot($this->parent) : $this); 
	}

	public function finalize() : void { /* no-op */ }
}

//
// Strings
//

class lexerString extends lexframe { 

	private bool $literal = FALSE, $multiline = FALSE; 
	private string $delim;

	public function __construct(Decoder $parent, string $char) { 

		$this->delim = $char;
		if($char == "'") $this->literal = TRUE; 

		parent::__construct($parent, $char); 

	}

	private bool $opened = FALSE;
	private string $lookahead = "";  

	public function lexc(string $char) : lexframe {


		// DEBUG
		\printf("> STRING:\t[%s] %s (%s) :%s\n", 
			$char,
			($this->literal ? 'l' : '-').($this->multiline ? 'm' : '-').($this->opened ? 'o' : '-'),
			$this->lookahead,
			$this->value
		);

		$this->parent->handleSpace($char); 

		$lct = Str\length($this->lookahead);

		if($char == $this->delim) { 
			// Is a delim

			// If we know it's not multiline, just call it quits here 
			if($this->opened && !($this->multiline)) { echo "asdf;\n"; return new lexerRoot($this->parent); }

			// Otherwise, start or continue the lookahead
			$this->lookahead .= $char; 
			$lct++;

			// Ending the string 
			if($lct == 3) { 
				if($this->opened) return new lexerRoot($this->parent); 
				else { 
					$this->opened = TRUE; 
					$this->multiline = FALSE; 
					return $this; 
				}
			}
			else return $this; 
		}

		else if ($lct == 1 && !($this->opened)) { 
			// Not a delim, still determining if opened or closed
			// So there's no character appending
			$this->lookahead = ""; 
			$this->opened = TRUE; 
			$this->multiline = FALSE; 
		}
		
		else if ($lct > 1) { 
			// Not a delim, but there's characters in the lookahead that need to be properly parsed
			// This happens when there's a double quote but not a triple quote 
			// The first lookahead thing is guaranteed to be a delim, hence >1 
			// If this happens, we know the string is not multiline 
			$this->value .= $this->lookahead;
			$this->lookahead = "";
			$this->opened = TRUE; 
			$this->multiline = FALSE;
		}

		//TODO: Escaping 
		$this->value .= $char; 
		return $this; 
	}

	public function finalize() : void { $this->addToken($this->multiline ? tokenType::STRING_MULTILINE : tokenType::STRING); }
}

newtype position = (int, int); 

class Decoder { 

	public function __construct() { 
		/* HH_IGNORE_ERROR[3004] */
		$this->lexer = new lexerRoot($this);
	}

	//
	// Lexing
	//

	private lexframe $lexer;

	private int $line = 1, $col = 1; 
	private vec<token> $lex = vec<token>[]; 
	public function getTokens() : vec<token> { return $this->lex; }

	public function getPosition() : position { return tuple($this->line, $this->col); }
	public function addToken(tokenType $type, (int, int) $pos, string $val = '') : void { 
		$this->lex[] = new token($type, $pos[0], $pos[1], $val); 
	}

	/**
	 * Handle character counts and whitespace.  Returns true if whitespace
	 */
	public function handleSpace(string $char) : bool { 
		switch($char) { 	

			case '\n':
				$this->line++;
				$this->col = 1; 
				return true; 

			case '\t':
				$this->col += 4;
				return true; 

			case ' ': 
				$this->col += 1;
				return true; 

			default:
				$this->col++;
				return false; 
		}
	}


	private function lex(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : void { 
		$file = \fopen($filename, "r", $use_include_path, $context);
		if($file === FALSE) throw new LogicException("FILE NOT FOUND");

		while(! \feof($file)) { 
			$string = \fread($file, 1024); 
			for($i = 0; $i < Str\length($string); $i++){ // > my syntax highlighter is broken lmao 
				
				// Process the character, replacing the current lexer if necessary
				$res = $this->lexer->lexc($string[$i]); 
				if($res !== $this->lexer) {
					$this->lexer->finalize();
					$this->lexer = $res; 
				}
			}

			$this->lexer->finalize(); // Finalize the last token 
		}
	}



	//
	// Parsing
	//

	private function parse() : dict<string, mixed> 
	{ 
		return dict<string, mixed>[]; //TODO 
	}



	// Main func

	public function DecodeFile(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : dict<string, mixed> { 
		$this->lex($filename, $use_include_path, $context);
		return $this->parse(); 
	}
}

function decodeFile(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : dict<string, mixed> { 
	return (new Decoder())->DecodeFile($filename, $use_include_path, $context);
}