namespace toml;

require_once __DIR__."/../vendor/hh_autoload.hh";

use \LogicException;
use \HH\Lib\Str;

// TODO: Line position here
class TOMLException extends \Exception {
	public function __construct(position $position, string $message) { 
		parent::__construct('At '.positionString($position).': '.$message); 
	}
}


//
// Lexing - tokens
//


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




//
// Lexer frames
// This is not implemented in a true stack; rather, there is one frame at a time, and frames can switch
// 	to one another by returning a new frame in lexc()
//


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

	/**
	 * Call this on EOF
	 */
	public function EOF() : void { $this->finalize(); }

	protected string $value = "";

	protected function addToken(tokenType $type) : void {
		$this->parent->addToken($type, $this->position, $this->value);  
	}

}
abstract class nestedLexer extends lexframe { }




class lexerRoot extends lexframe { 

	private bool $isBareKey = false; 
	private bool $isOperator = false; 

	public function lexc(string $char) : lexframe {

		// DEBUG
		\printf("> ROOT:\t\t[%s] %s :%s\n", $char, ($this->isBareKey ? 'b' : '-').($this->isOperator ? 'o' : '-'), $this->value);

		// Whitespace - end current token if necessary 
		if(\ctype_space($char)) { 
			if(Str\length($this->value) == 0) { 
				$this->position = $this->parent->getPosition();
				return $this; 
			}
			else return new lexerRoot($this->parent); 
		}

		// See if the character could belong to an unquoted "bare" key 
		if(\ctype_alnum($char) || $char == '-' || $char == '_') 
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
					throw new TOMLException($this->position, \sprintf('Unrecognized token "%s"', $this->value));
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
	public function isMultiline() : bool { return $this->multiline; }

	public function __construct(Decoder $parent, string $char) { 

		$this->delim = $char;
		if($char == "'") $this->literal = TRUE; 

		parent::__construct($parent, $char); 

	}

	private bool $opened = FALSE;
	private string $lookahead = ""; 

	private bool $trimmingWS = FALSE;
	private bool $trimmingNewline = FALSE; 
	public function trimCurrentWhitespace() : void { 
		$this->trimmingWS = TRUE; 
		$this->wsTrimmingPosition = $this->parent->getPosition();
	} 

	private ?position $wsTrimmingPosition;
	private string $wsTrimmingString = ""; 

	public function lexc(string $char) : lexframe {


		// DEBUG
		\printf("> STRING:\t[%s] %s (%s) :%s\n", 
			$char,
			($this->literal ? 'l' : '-').($this->multiline ? 'm' : '-').($this->opened ? 'o' : '-'),
			$this->lookahead,
			$this->value
		);

		//
		// Delimiter handling
		// We want to do this before the other stuff since it determines the $opened and $multiline variables
		//

		$lct = Str\length($this->lookahead);
		if($char == $this->delim) { 
			// Is a delim

			// If we know it's not multiline, just call it quits here 
			if($this->opened && !($this->multiline)) { return new lexerRoot($this->parent); }

			// Otherwise, start or continue the lookahead
			$this->lookahead .= $char; 
			$lct++;

			// Ending the delimiter 
			if($lct == 3) { 
				if($this->opened) return new lexerRoot($this->parent); // Closing delimiter
				else { 
					$this->opened = TRUE; 
					$this->multiline = TRUE; 
					$this->trimmingNewline = TRUE; 
					$this->lookahead = "";
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

		//
		// Escape sequences
		//
		if($char == '\\' && !($this->literal)) return new lexerEscape($this); 

		//
		// Whitespace handling
		//
		
		if($this->trimmingWS) { 
			// Trimming whitespace - triggered by a line-ending backslash in a basic multiline string
			if(\ctype_space($char)) {
				$this->wsTrimmingString .= $char; 
				return $this; 
			}
			else {
				// The whitespace followed by the backslash doesn't contain a newline, which makes it an invalid escape 
				if(!(Str\contains($this->wsTrimmingString, "\n"))) {
					if($pos = $this->wsTrimmingPosition) throw new TOMLException($pos, "Invalid escape sequence - is this supposed to be a line-ending backslash?");
					else throw new LogicException("During invalid line-ending backslash handling - the position is null");
				}

				$this->wsTrimmingString 	= "";
				$this->wsTrimmingPosition 	= NULL; 
				$this->trimmingWS 			= FALSE; 
			}
		}
		if($this->trimmingNewline) { 
			// Trimming newline - happens immediately after the opening delimiter of any multiline string
			if($char == "\n") {
				$this->trimmingNewline = FALSE; 
				return $this; 
			}
			else 						$this->trimmingNewline = FALSE;
		}

		// Illegal line ending in non-multiline string 
		if($char == "\n" && !($this->opened && $this->multiline)) {
			throw new TOMLException($this->position, "Unexpected line ending in non-multiline string"); 
		}
		
		// If none of these conditions are met, just append the character and carry on 
		$this->value .= $char; 
		return $this; 
	}

	public function finalize() : void { $this->addToken($this->multiline ? tokenType::STRING_MULTILINE : tokenType::STRING); }
	public function EOF() : void { throw new TOMLException($this->position, "Unexpected EOF - unclosed string literal"); }

	public function append(string $str) : void { $this->value .= $str; }
}




class lexerEscape extends nestedLexer { 

	private lexerString $string; 

	private ?int $unicodeLength; 

	public function __construct(lexerString $parent) { 
		$this->string = $parent; 
		parent::__construct($parent->parent); 
	}

	public function lexc(string $char) : lexframe { 

		// DEBUG
		\printf("> ESC\t\t[%s]", $char);

		// Is gathering a unicode string
		if($ulen = $this->unicodeLength) { 

			// Invalid characters
			if(!(\ctype_xdigit($char))) throw new TOMLException($this->position, \sprintf('Expected %d hex digits (0-9, a-f, A-F), got %s', $ulen ?? '0', $char));

			// Exit conditions
			$len = Str\length($this->value);
			if($len === $ulen) {
				for($i = 0; $i < $ulen; $i += 2) $this->string->append(\chr(\hexdec($this->value[$i].$this->value[$i+1]))); 
				return $this->string; 
			}
			else return $this;

		} else {
			// Start of the escape sequence

			if(\ctype_space($char) && $this->string->isMultiline()) {
				// Backslash followed by whitespace
				// Should be a line-ending backslash - this will be verified in lexerString
				$this->string->trimCurrentWhitespace();
				return $this->string; 
			}
			else switch($char) {
				// Single-char escapes
				case '"':  $this->string->append('"');	return $this->string;
				case 'b':  $this->string->append("\b");	return $this->string;
				case 't':  $this->string->append("\t");	return $this->string;
				case 'n':  $this->string->append("\n");	return $this->string;
				case 'f':  $this->string->append("\f");	return $this->string;
				case 'r':  $this->string->append("\r");	return $this->string;
				case '\\': $this->string->append("\\");	return $this->string;

				// Unicode sequences
				case 'u':
					$this->unicodeLength = 4; 
					return $this; 
				case 'U':
					$this->unicodeLength = 8; 
					return $this; 

				default:
					throw new TOMLException($this->position, \sprintf("Unrecognized escape character '%s'", $char));
			}
		}
	}

	public function finalize() : void { /* No-op - all string handling for the parent is done in this::lexc */ }
	public function EOF() : void { throw new TOMLException($this->position, "Unexpected EOF - incomplete escape sequence"); }
}



//
//
// Root decoder class
//
//




newtype position = (int, int); 

function positionString(position $position) : string { return \sprintf('(%d,%d)', $position[0], $position[1]); }

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
	private function handleSpace(string $char) : bool { 
		switch($char) { 	

			case "\n":
				$this->line++;
				$this->col = 1; 
				return true; 

			case "\t":
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

				$char = $string[$i];
				$this->handleSpace($char);
				
				// Process the character, finalizing if the lexer changes 
				$res = $this->lexer->lexc($char); 
				if(!($this->lexer === $res || $res is nestedLexer)) $this->lexer->finalize();
				$this->lexer = $res; 
			}
		}

		$this->lexer->EOF();
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