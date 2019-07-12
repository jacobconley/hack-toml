namespace toml;

require_once __DIR__."/../vendor/hh_autoload.hh";

use \LogicException;
use \HH\Lib\{ Str, Regex, Vec }; 

class TOMLException extends \Exception {
	public function __construct(?position $position, string $message) { 
		if($position = $position) parent::__construct('At '.positionString($position).': '.$message); 
		else parent::__construct($message); 
	}
}
class TOMLUnexpectedException extends TOMLException { 
	public function __construct(Token $token) {
		parent::__construct($token->getPosition(), 'Unexpected '.$token->getTypeString());
	}
}


//
// Lexing - tokens
//


enum tokenType : int { 
	KEY 				= 0; 

	INTEGER				= 10;
	FLOAT 				= 11;
	BOOL 				= 12;
	DATETIME			= 13;
	STRING 				= 15; 
	STRING_M			= 16;

	OP_EQUALS 			= 20;
	OP_DOT 				= 21;
	OP_COMMA 			= 22;

	OP_BRACKET_OPEN		= 30;
	OP_BRACKET_CLOSE 	= 31;
	OP_DB_BRACKET_OPEN	= 32;
	OP_DB_BRACKET_CLOSE	= 33;

	OP_BRACE_OPEN 		= 35;
	OP_BRACE_CLOSE 		= 36;

	EOL 				= 50;
	EOF 				= 51;
	COMMENT 			= 55;

	ERROR 				= 100;
}

enum valueType : int { 

	INTEGER				= 10;
	FLOAT 				= 11;
	BOOL 				= 12;
	DATETIME			= 13;
	STRING 				= 15; 

	INLINE_DICT 		= 71;
	ARRAY 				= 80;

	EMPTY 				= 91; 

}


class Token { 

	public function toString() : string { 
		return \sprintf("(%s,%s)\t%d\t:%s", $this->line, $this->col, $this->type, $this->text);
	}

	private int $line;
	private int $col;
	private string $text;
	private tokenType $type;

	public function getLine() : int 		{ return $this->line; }
	public function getCol()  : int 		{ return $this->col;  }
	public function getText() : string 		{ return $this->text; }
	public function getType() : tokenType 	{ return $this->type; }

	public function getPosition() : position { return tuple($this->line, $this->col); }

	public function __construct(tokenType $type, int $line, int $col, string $text = ''){
		$this->line = $line;
		$this->col = $col;
		$this->text = $text;
		$this->type = $type;
	}

	public static function EnumToString(int $val) : ?string { 
		switch($val) { 
			case tokenType::KEY: 		return 'Bare key';
			case tokenType::INTEGER: 	return 'Integer';
			case tokenType::FLOAT: 		return 'Float';
			case tokenType::BOOL: 		return 'Boolean';
			case tokenType::DATETIME: 	return 'DateTime';
			case tokenType::STRING:		return 'String';
			case tokenType::STRING_M: 	return 'Multi-line string';

			case tokenType::EOL: 		return "end-of-line";
			case tokenType::EOF: 		return "end-of-file";
			case tokenType::COMMENT: 	return "comment";

			case tokenType::OP_COMMA: 	return "comma (,)";
			case tokenType::OP_EQUALS:	return "equals sign (=)";
			case tokenType::OP_DOT: 	return "dot (.)";

			case valueType::INLINE_DICT:return "Inline table";
			case valueType::ARRAY: 		return "Array";
			case valueType::EMPTY: 		return "Empty";
			default: 					return NULL;
		}
	}

	public function getTypeString() : string { return Token::EnumToString((int) $this->type) ?? $this->text; }

	public function isEndAnchor() : bool { return ($this->type == tokenType::EOL) || ($this->type == tokenType::EOF); }
	public function isKey() : bool { 
		if($this->type == tokenType::KEY || $this->type == tokenType::STRING) return TRUE;
		if(Regex\matches($this->text, re"/^[a-zA-Z0-9_-]+\b/")) return TRUE; 
		return FALSE; 
	}

	public function getValueType() : ?valueType { 
		switch($this->type) { 
			case tokenType::INTEGER:			return valueType::INTEGER;
			case tokenType::FLOAT: 				return valueType::FLOAT;
			case tokenType::BOOL: 				return valueType::BOOL;
			case tokenType::DATETIME:			return valueType::DATETIME;
			case tokenType::STRING: 			return valueType::STRING;
			case tokenType::STRING_M:			return valueType::STRING;
			default: 							return NULL;
		}
	}

	public function getValue() : nonnull { 
		if($type = $this->getValueType()) {
			switch($type) {

				case valueType::INTEGER: 
					$text = $this->text;		
					$text =	Str\replace($text, '_', ''); 		// Idk if PHP handles underscores, docs are shit 
					$text = Str\replace($text, '0o', '0'); 	// Since the validity was guaranteed earlier, the only 0o could be at the beginning
																	// intval() uses a leading 0 to mean it's octal 

					return \intval($text);

				case valueType::FLOAT: 			
					$text =	Str\replace($this->text, '_', ''); 		
					return \doubleval($text);

				case valueType::BOOL:
					if($this->text === "true") return TRUE;
					else return FALSE;


				case valueType::STRING: 		return $this->text;
				case valueType::DATETIME:		return new \DateTime($this->text);

				default:						throw new LogicException("Type not handled in value()");
			}
		}
		else throw new LogicException("This Token is not a value type");
	}
}



//
//
// Lexing
//
//



class Lexer { 

	protected Decoder $parent;
	protected int $line = 1; 

	public function __construct(Decoder $parent) { 
		$this->parent = $parent;
	}


	// 
	// Helper functions
	//

	protected final function getPosition() : position { return tuple($this->line, $this->n + 1); }
	public final function getLineNum() : int { return $this->parent->getLineNum(); }
	public final function getParent() : Decoder { return $this->parent; }

	private function token(tokenType $type, string $value) : void {
		\printf("\n\nTOKEN: %s '%s'\n", Token::EnumToString((int) $type), $value); // DEBUG
		$this->parent->handleToken(new Token($type, $this->line, $this->n, $value));  
		$this->n += Str\length($value); 
	}

	protected final function try<T as Regex\Match>(Regex\Pattern<T> $pattern) : ?Regex\Match { 		
		if($match = Regex\first_match($this->lineText, $pattern, $this->n)) { 
			/* HH_IGNORE_ERROR[4108] The field 0 is always defined - bad typechecker! */
			$this->n += Str\length($match[0]); 
			return $match;
		}
		else return NULL; 
	}

	protected final function is(string $str) : ?string { 
		$len = Str\length($str);
		if(Str\starts_with($this->lineText, $str)) { 
			return $str;
		} 
		else return NULL;
	}

	//
	// Lexing
	//


	private int $n = 0;
	private string $lineText = '';  // dummy init value 

	private ?StringHandler $StringHandler; 


	public final function EOL() : void { 
		if($handler = $this->StringHandler) if($handler->isMultiline()) return; 
		$this->parent->handleToken(new Token(tokenType::EOL, $this->line, 0));
	}

	public final function EOF() : void { 
		if($this->StringHandler) throw new TOMLException(NULL, "Unexpected end-of-file in string literal");
		$this->parent->handleToken(new Token(tokenType::EOF, $this->line, 0));
	}



	/**
	 * Process the current character $char.  Return $this to keep current frame, nonnull to replace, null to pop 
	 */
	public final function handleLine(string $line, int $lineNum, int $offset = 0) : void { 
		\printf("\n\n---------------\nLINE: %s\n", $line); // DEBUG

		$this->line 	= $lineNum; 
		// $this->lineText = $line; 
		$this->n 		= $offset; 

		while($this->n < \strlen($line)) { 
			$n = $this->n; 
			$this->lineText = Str\slice($line, $n); 
			// \printf("AT %d - '%s'\n", $n, $this->lineText); // DEBUG

			// First - see if there is a string context
			// If there is, it will return a new $n offset to skip to if it finishes, or NULL which means it continues into the next line as well
			if($handler = $this->StringHandler) { 
				// Remember the string handler uses the entire line, as opposed to the main lexer which slices off each token
				if($newOffset = $handler->handleLine($line, $lineNum, $n)) { 
					// String is ending, its token has already been handled by the StringHandler so we advance to the new offset
					$this->StringHandler = NULL;
					$this->n = $newOffset; 
					continue;
				}
				else return; 
			}

			if(\ctype_space($line[$n])){ $this->n++; continue; }

			if($line[$n] == "#") return; // Ignore rest of line starting at comment


			//
			// "Normal" lexing
			//

			//
			// Looking for strings first 
			// 

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('"""')) { 
				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
				$this->n += 3; // have to manually increment since we're not calling token 
				continue;
			}

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is("'''")) { 
				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
				$this->n += 3; // have to manually increment since we're not calling token 
				continue;
			}

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('"')) {
				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
				$this->n++; // have to manually increment since we're not calling token 
				continue;
			}

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is("'")) { 
				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
				$this->n++; // have to manually increment since we're not calling token 
				continue;
			}

			//
			// Operators
			//

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('[[')) { $this->token(tokenType::OP_DB_BRACKET_OPEN, $match); 	continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is(']]')) { $this->token(tokenType::OP_DB_BRACKET_CLOSE, $match); 	continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('['))  { $this->token(tokenType::OP_BRACKET_OPEN, $match); 		continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is(']'))  { $this->token(tokenType::OP_BRACKET_CLOSE, $match); 		continue; } 
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('{'))  { $this->token(tokenType::OP_BRACE_OPEN, $match); 			continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('}'))  { $this->token(tokenType::OP_BRACE_CLOSE, $match); 		continue; } 
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('.'))  { $this->token(tokenType::OP_DOT, $match); 				continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('='))  { $this->token(tokenType::OP_EQUALS, $match); 				continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is(','))  { $this->token(tokenType::OP_COMMA, $match); 				continue; }


			//
			// Value types 
			// 

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('true')) 	{ $this->token(tokenType::BOOL, $match); 	continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('false')) { $this->token(tokenType::BOOL, $match); 	continue; }

			// Datetime 
			if($match = Regex\first_match($this->lineText, re"/^\d{4}-\d\d-\d\d(T| )\d\d:\d\d:\d\d(\.\d+)?(Z|((\+|-)\d\d:\d\d))?/")) { 
				$this->token(tokenType::DATETIME, $match[0]); 	
				continue; 
			}

			// Number
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = Regex\first_match($this->lineText, re"/^0x[0-9a-f_]+|^0o[0-7_]|^0b[01_]|^[\+-]?(inf|nan|(0|[1-9]([0-9_])*(\.[0-9_]+)?)([eE][\+-]?[0-9_]+)?)/")) { 
				if(!(Str\is_empty($match[4]) && Str\is_empty($match[5])) || Str\starts_with($match[0], '0')) 	$this->token(tokenType::FLOAT, $match[0]); 
				else 																							$this->token(tokenType::INTEGER, $match[0]); 

				continue; 
			}

			// Bare keys
			if($match = Regex\first_match($this->lineText, re"/^[a-zA-Z0-9_-]+\b/"))
			{
				$this->token(tokenType::KEY, $match[0]);
				continue; 
			}

			throw new TOMLException($this->getPosition(), \sprintf("Unrecognized input starting at '%s'", Str\slice($line, $this->n, 4)));
		}
	}
}


class StringHandler { 
	private Lexer $parent; 

	private string $value = ""; 
	private position $pos; 

	private string $delim; 
	private bool $literal, $multiline; 

	public final function isMultiline() : bool { return $this->multiline; }

	public function __construct(Lexer $parent, position $pos, string $delim) { 
		$this->parent = $parent; 
		$this->pos = $pos; 
		$this->delim = $delim; 

		switch($delim) { 
			case '"':		$this->literal = FALSE; $this->multiline = FALSE; 	break;
			case "'":		$this->literal = TRUE; 	$this->multiline = FALSE; 	break;
			case '"""':		$this->literal = FALSE; $this->multiline = TRUE; 	break; 
			case "'''":	 	$this->literal = TRUE; 	$this->multiline = TRUE; 	break; 
			default: 		throw new LogicException("Unrecognized delimiter in string handler");
		}

	}


	private bool $opened = FALSE; 
	private bool $trimmingWS = FALSE; 
	public function trimWS() : void { $this->trimmingWS = TRUE; }

	// Returns NULL if string is still going, or offset if it ends
	
	public final function handleLine(string $line, int $lineNum, int $offset) : ?int
	{ 

		\printf("STRING LINE at %d: %s\n", $offset, $line); 


		// Newline immediately following opening multiline delim, ignored and continued 
		if($this->multiline && !($this->opened) && Str\is_empty($line)) { $this->opened = TRUE; return NULL; }
		$this->opened = TRUE; 

		if($this->trimmingWS) { 
			$max = Str\length($line) - 1; 
			for($i = $offset; $i <= $max; $i++) { 
				if(\ctype_space($line[$i])) continue; 

				if($i == $max) return $max; // Line ended with no word characters

				$offset = $i; 
				$this->trimmingWS = FALSE; 
				break; 
			}
		}

		for($i = $offset; $i < Str\length($line); $i++) { 
			$char = $line[$i];

			// Escape sequence
			if($char == '\\' && !($this->literal)) { 
				if($match = Regex\first_match($line, re"/^\\\\(U[a-fA-F0-9]{8}|u[a-fA-F0-9]{4}|.)/", $i + 1)) { 

					$char = $match[1][0];

					// Unicode encoding
					if($char == 'u' || $char == 'U') { 
						$len = ($char == 'u' ? 4 : 8);
						for($x = 1; $x <= $len; $x += 2) $this->value .= \hexdec($match[1][$x].$match[1][$x + 1]);
						$i += $len;
						continue;
					}

					// Escape sequence
					switch($match[1][0]) { 
						case 'b': 	$this->value .= "\b";  break;
						case 't': 	$this->value .= "\t";  break; 
						case 'n': 	$this->value .= "\n";  break; 
						case 'f': 	$this->value .= "\f";  break; 
						case 'r': 	$this->value .= "\r";  break; 
						case '\\': 	$this->value .= "\\";  break; 
						case '"': 	$this->value .= '"';   break; 
						default: throw new LogicException('Matched escape literal not handled in following switch');
					}

					$i += 2; 
					continue; 

				}
				else throw new TOMLException(tuple($lineNum, $i), "Unrecognized escape sequence '".$char."'"); 
			} 


			// handling closing delimiter
			if($char == $this->delim[0]) {

				$len = Str\length($this->delim);  

				if($this->multiline) 
				{ 
					// Incomplete closer
					if(Str\slice($line, $i, $len) != $this->delim) { 
						$this->value .= $char; 
						continue; 
					}
				}


				\printf("\nSTRING: '''%s'''\n", $this->value); // DEBUG

				$this->parent->getParent()->handleToken(new Token(
					$this->multiline ? tokenType::STRING_M : tokenType::STRING,
					$this->pos[0], $this->pos[1],
					$this->value
				));
				return $i + $len;
			} 

			$this->value .= $char;
		}

		if($this->multiline) { 
			$this->value .= "\n";
			return NULL; 
		}
		else throw new TOMLException(tuple($lineNum, $i), "Incomplete string literal"); 
	}
}














//
//
// Grammatical analysis
//
//





abstract class parserContext 
{

	protected Decoder $decoder; 
	public function __construct(Decoder $decoder) {
		$this->decoder = $decoder;
	}

	public abstract function handleToken(Token $token) : void;

	protected function pop() : void { $this->decoder->parserPop(); }
}


interface parser_value {
	require extends parserContext;
	public function handleValue(Token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void; 
}








//
//
// Body parsing
//
//




class parserBase extends parserContext implements parser_value { 

	//
	// Data handling
	//

	protected dict<string, nonnull> $dict = dict<string, nonnull>[]; 
	public function getDict() : dict<string, nonnull> { return $this->dict; }


	private function keystr(vec<string> $key) : string { 
		$str = '';
		for($i = 0; $i < \count($key); $i++) {
			if($i > 0) $str .= '.'; 
			$str .= $key[$i];
		}
		return $str; 
	}

	private function _addKV(vec<string> $key, Token $keyToken, nonnull $value, inout dict<string,nonnull> $dict) : void { 
		$count = \count($key);
		if($count == 0) throw new LogicException("Empty key");

		else if($count == 1) { 
			if(\array_key_exists($key[0], $dict)) throw new TOMLException($keyToken->getPosition(), \sprintf('Duplicate key "%s"', $this->keystr($key))); 
			$dict[$key[0]] = $value; 
			return;
		}

		else {

			$x = $key[0];

			$y = idx($dict, $x, dict<string,nonnull>[]); 

			/* HH_IGNORE_ERROR[4101] Generics */
			if(!($y is dict)) throw new TOMLException($keyToken->getPosition(), \sprintf('"%s": %s is not a table', $this->keystr($key), $x));
			/* HH_IGNORE_ERROR[4110] handled by the above*/
			$this->_addKV(Vec\slice($key, 1), $keyToken, $value, inout $y); 
			$dict[$x] = $y;
		}
	}


	private function _appendKV(vec<string> $key, Token $keyToken, dict<string,nonnull> $value, inout dict<string,nonnull> $dict) : void { 
		$count = \count($key);
		if($count == 0) throw new LogicException("Empty key");

		else if($count == 1) { 
			$thing = idx($dict, $key[0], vec<dict<string, nonnull>>[]);
			/* HH_IGNORE_ERROR[4101] Generics */
			if($thing is vec) { 
				$thing[] = $value;
				$dict[$key[0]] = $thing;
				return; 
			}
			/* HH_IGNORE_ERROR[4101] Generics */
			else throw new TOMLException($keyToken->getPosition(), \sprintf('"%s" is not an array of tables', $key[0]));
		}

		else {

			$x = $key[0];

			$y = idx($dict, $x, dict<string,nonnull>[]); 

			/* HH_IGNORE_ERROR[4101] Generics */
			if(!($y is dict)) throw new TOMLException($keyToken->getPosition(), \sprintf('"%s": %s is not a table', $this->keystr($key), $x));
			/* HH_IGNORE_ERROR[4110] handled by the above*/
			$this->_appendKV(Vec\slice($key, 1), $keyToken, $value, inout $y); 
			$dict[$x] = $y;
		}
	}

	public function addKeyValue(nonnull $value) : void { 
		$dict = $this->dict; 
		if($key = $this->key) {
			if($token = $this->keyToken) $this->_addKV($key, $token, $value, inout $dict); 
		}
		else throw new LogicException("Handling value without key");

		$this->dict 	= $dict; 
		$this->key 		= NULL;
		$this->keyToken = NULL;
	}
	public function appendKeyValue(dict<string, nonnull> $value) : void 	{ 
		$dict = $this->dict; 
		if($key = $this->key) {
		 	if($token = $this->keyToken) $this->_appendKV($key, $token, $value, inout $dict); 
		 }
		else throw new LogicException("Handling value without key");

		$this->dict 	= $dict; 
		$this->key 		= NULL;
		$this->keyToken = NULL;
	}

	//
	// Parser context
	//

	protected ?vec<string> $key;
	protected ?Token $keyToken;
	public function handleKey(vec<string> $key, Token $token) : void { 

		\printf("KEY at %s:\n", positionString($token->getPosition()));
		\print_r($key);// DEBUG
		echo "\n";

		if($this->key is nonnull) throw new LogicException("A key has been handled and not cleared"); 
		$this->key = $key; 
		$this->keyToken = $token;
	}

	public function getKey() : ?vec<string> { return $this->key; }

	public function handleValue(Token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void { 
		$valuestr = $value;
		/* HH_IGNORE_ERROR[4101] Generic argument */
		if($value is vec || $value is dict) $valuestr = "--";
		\printf("VALUE of type %s (%s): %s\n", Token::EnumToString((int) $type), $subtype == null ? 'none' : Token::EnumToString((int) $subtype), $valuestr); // DEBUG

		$this->addKeyValue($value); 
		$this->expectLineEnd = TRUE; 
	}

	protected bool $expectEquals = FALSE; 
	protected bool $expectLineEnd = FALSE; 


	// Helper function to deal with a potential key, returning TRUE if that works
	// Sorry, bad function name lmao 
	protected function doParseKey(Token $token) : bool {
		if($token->isKey()) { 
			$kp = new parserKey($this);
			$kp->handleToken($token); 
			$this->decoder->parserPush($kp); 

			return TRUE;
		}
		else return FALSE; 
	}

	//
	// Main method
	//

	public function handleToken(Token $token) : void 
	{ 
		//
		// Context expectations
		//

		// Line end
		if($this->expectLineEnd) { 
			if($token->isEndAnchor()) { 
				$this->expectLineEnd = FALSE;
				return;
			}
			else throw new TOMLException($token->getPosition(), "Expected end-of-line"); 
		}


		// Equals sign 
		if($this->key) { 
			if($token->getType() == tokenType::OP_EQUALS) {
				$this->expectEquals = FALSE; 
				$this->decoder->parserPush(new parserValue($this));
				return;  
			}
			else throw new TOMLException($token->getPosition(), "Expected equals sign (=) after key");
		}
		else if($token->getType() == tokenType::OP_EQUALS) throw new TOMLUnexpectedException($token); 

		//
		// No context - beginning of parse tree:
		//

		if($this->doParseKey($token)) return; 

		if($this->key === NULL && $token->isEndAnchor()) return; // Ignore empty lines

		else throw new TOMLUnexpectedException($token); 
	}
}

//
// The special instance of the parser that is at the bottom of the stack 
//
class parserRoot extends parserBase { 


	public function __construct(Decoder $decoder) {
		parent::__construct($decoder);
	}


	public function handleToken(Token $token) : void { 

		switch($token->getType()) { 

			case tokenType::OP_BRACKET_OPEN:
				$block = new parserDictBody($this);
				$this->decoder->parserPush($block);
				return;

			case tokenType::OP_DB_BRACKET_OPEN:
				$block = new parserDictArrayBody($this);
				$this->decoder->parserPush($block);
				return; 


			default:
				parent::handleToken($token); 
				return; 
		}
	}
}




//
//
// Phrase parsing
//
//


//
// Key-Value
//



/**
 * Parses a key, then invokes the handleKey() method of its parent parserBase and pops itself off.  
 * Should always be on top of parserRoot or parserDict 
 */
class parserKey extends parserContext { 

	private parserBase $parent; 
	private vec<string> $keys = vec<string>[]; 

	public function __construct(parserBase $parent) { 
		$this->parent = $parent; 
		parent::__construct($parent->decoder);
	}

	private bool $expectKey = TRUE; 

	public function handleToken(Token $token) : void 
	{ 
		\printf("Key token %s\n", $token->getText()); // DEBUG

		if($this->expectKey) 
		{ 
			if($token->isKey()) { 
				$this->keys[] = $token->getText(); 
				$this->expectKey = FALSE;
			}
			else throw new TOMLException($token->getPosition(), "Expected a key following the dot (.)"); 
		}

		else if($token->getType() == tokenType::OP_DOT) { 
			$this->expectKey = TRUE;
			return; 
		}

		else { 
			$this->pop();
			$this->parent->handleKey($this->keys, $token); 
			$this->parent->handleToken($token); 
		}
	}
}

class parserValue extends parserContext implements parser_value { 
	private parser_value $parent;

	public function __construct(parser_value $parent) { 
		$this->parent = $parent; 
		parent::__construct($parent->decoder);
	}

	public function handleToken(Token $token) : void { 
		if($type = $token->getValueType()) { 
			$this->decoder->parserPop();
			$this->parent->handleValue($token, $token->getValue(), $type);
			return; 
		}

		else if($token->getType() == tokenType::OP_BRACE_OPEN) { 
			$this->decoder->parserPush(new parserInlineDict($this, $token));
			return;
		}

		else if($token->getType() == tokenType::OP_BRACKET_OPEN) { 
			$this->decoder->parserPush(new parserArray($this, $token)); 
		}

		else throw new TOMLException($token->getPosition(), "Expected a value type here, got ".Token::EnumToString((int) $token->getType())); 
	}

	public function handleValue(Token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void { 
		if($this->parent !== $this) $this->decoder->parserPop(); // keeps root from popping itself
		$this->parent->handleValue($token, $value, $type, $subtype); 
	}
}



//
// Complex value types
//



class parserArray extends parserContext implements parser_value { 
	private parserValue $parent; 
	private vec<nonnull> $vec = vec<nonnull>[]; 
	private ?valueType $subtype; 
	private Token $init; 

	private bool $expectValue = TRUE; 

	public function __construct(parserValue $parent, Token $init) { 
		$this->parent = $parent; 
		$this->init = $init; 
		parent::__construct($parent->decoder);
	}

	public function handleToken(Token $token) : void {
		if($token->getType() == tokenType::EOF) throw new TOMLUnexpectedException($token); // Incomplete array
		if($token->getType() == tokenType::EOL) return; // Ignore newlines in array

		if($token->getType() == tokenType::OP_BRACKET_CLOSE) {
			$this->decoder->parserPop();
			$this->parent->handleValue($this->init, $this->vec, valueType::ARRAY, $this->subtype ?? valueType::EMPTY); 
			return;
		}

		if($this->expectValue) { 
			$parser = new parserValue($this); 
			$this->decoder->parserPush($parser); 
			$parser->handleToken($token); 
			return; 
		}
		else if($token->getType() == tokenType::OP_COMMA) { 
			$this->expectValue = TRUE; 
			return; 
		}
		else throw new TOMLUnexpectedException($token);
	}


	public function handleValue(Token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void { 

		if($this->subtype != NULL && $type!= $this->subtype) throw new TOMLException($token->getPosition(), \sprintf('Member of type %s in array previously of type %s', 
			Token::EnumToString((int) $type) ?? '-', 
			Token::EnumToString((int) $this->subtype) ?? '-'));
		else $this->subtype = $type; 
		
		$this->vec[] = $value; 
		$this->expectValue = FALSE; 
	}
}





//
// An override of the parser that expects commas instead of line ends
//
class parserInlineDict extends parserBase { 
	private parserValue $parent; 
	private Token $init; 

	public function __construct(parserValue $parent, Token $init) { 
		$this->parent = $parent; 
		$this->init = $init; 
		parent::__construct($parent->decoder);
	}


	public function handleToken(Token $token) : void {

		if($token->getType() == tokenType::OP_BRACE_CLOSE) { 
			$this->decoder->parserPop();
			$this->parent->handleValue($this->init, $this->dict, valueType::INLINE_DICT); 
			return; 
		}

		if($this->expectLineEnd) {
			if($token->getType() == tokenType::OP_COMMA) { 
				$this->expectLineEnd = FALSE; 
				return; 
			}
			else throw new TOMLException($token->getPosition(), "Expected comma (,) to separate entries in inline table"); 
		}

		parent::handleToken($token); 
	}
}





//
//
// Section parsing
//
//





/**
 * Parser context representing the body of a [dictionary] 
 * It continues until another dictionary or EOF 
 */
class parserDictBody extends parserRoot {
	private parserRoot $parent; 
	public function __construct(parserRoot $parent) { 
		$this->parent = $parent; 
		parent::__construct($parent->decoder);
	}

	private bool $opened = FALSE; 

	public function handleToken(Token $token) : void 
	{
		// Gotta override this in two ways:
		// 1) Handling the declaration stage, when $this->opened is FALSE 
		// 2) Handling the end of this table, at which point control should pass to the next context in the stack

		\printf("DICT BODY TOKEN: %s\n", $token->getText()); 

		if($this->opened)
		{
			// End of the table 
			if($token->getType() == tokenType::OP_BRACKET_OPEN || $token->getType() == tokenType::EOF) 
			{
				$this->pop(); 
				$this->parent->addKeyValue($this->dict); 
				$this->parent->handleToken($token); 
				return; 
			}

			// Calling the parent implementation here, as opposed to passing control to the parent context instance
			else parent::handleToken($token); 
		}
		else { 

			// Finishing up the declaration stage - coupled to the below 

			if($this->key === NULL) { 
				if($this->doParseKey($token)) return; // The rest of the key handling will be done below on bracket close
				else throw new TOMLException($token->getPosition(), "Expected a key in [table] declaration"); 
			}

			if($token->getType() == tokenType::OP_BRACKET_CLOSE) {
				if($key = $this->key) { 
					$this->parent->handleKey($key, $token);
					$this->key 		= NULL;
					$this->opened 	= TRUE; 
					\printf("Opened dict: %s\n", $key[\count($key) - 1]); // DEBUG
					return; 
				}
				else throw new TOMLException($token->getPosition(), "Expected a key name in [table] declaration"); 
			}
			else throw new TOMLUnexpectedException($token); 

		}
	}
}

// See the notes above on how this class overrides the root context
class parserDictArrayBody extends parserRoot { 
	private parserRoot $parent; 
	public function __construct(parserRoot $parent) { 
		$this->parent = $parent; 
		parent::__construct($parent->decoder);
	}

	private bool $opened = FALSE; 

	public function handleToken(Token $token) : void 
	{

		if($this->opened)
		{
			// End of the dictionary 
			if($token->getType() == tokenType::OP_DB_BRACKET_OPEN || $token->getType() == tokenType::EOF) 
			{ 
				$this->pop(); 
				$this->parent->appendKeyValue($this->dict); 
				$this->parent->handleToken($token); 
				return;
			}

			else parent::handleToken($token); 
		}
		else { 

			// Finishing up the declaration stage 

			if($this->key === NULL) { 
				if($this->doParseKey($token)) return; 
				else throw new TOMLException($token->getPosition(), "Expected a key in [[dictionary array]] declaration"); 
			}

			if($token->getType() == tokenType::OP_DB_BRACKET_CLOSE) {
				if($key = $this->key) { 
					$this->parent->handleKey($key, $token);
					$this->key 		= NULL;
					$this->opened 	= TRUE;
					return; 
				}
				else throw new TOMLException($token->getPosition(), "Expected a key in [[dictionary array]] declaration"); 
			}
			else throw new TOMLUnexpectedException($token); 

		}
	}
}





//
//
// Main decoder class
//
//








newtype position = (int, int); 

function positionString(position $position) : string { return \sprintf('(%d,%d)', $position[0], $position[1]); }

class Decoder { 
	private ?Lexer $lexer;
	private Vector<parserContext> $parsers = Vector<parserContext>{};

	public function getLexer() : Lexer { 
		if($lexer = $this->lexer) return $lexer;
		else throw new LogicException("NO LEXER SET");
	} 


	// DEBUG
	private vec<Token> $tokens = vec<Token>[]; 
	public function getTokens() : vec<Token> { return $this->tokens; }

	public function handleToken(Token $token) : void { 

		if($p = $this->parsers->lastValue()) { 
			$p->handleToken($token); 
		}
		else throw new LogicException("No parsers on the stack"); 
	}

	public function parserPush(parserContext $parser) : void { 
		\printf("PUSH\n"); // DEBUG
		$this->parsers->add($parser); 
	}
	public function parserPop() : void { 
		\printf("POP\n"); // DEBUG
		$this->parsers->pop(); 
	}


	private int $lineNum = 1;
	public function getLineNum() : int { return $this->lineNum; }

	private string $line = "";
	private function parseBuffer(string $buf) : void { 

		for($i = 0; $i < Str\length($buf); $i++){

			$char = $buf[$i];

			if($char == "\r") continue; // Flat-out ignoring carriage returns, don't think this is a bad idea (?)

			if($char == "\n") { 
				$this->lineNum++; 
				if($lexer = $this->lexer) {
					$lexer->handleLine($this->line, $this->lineNum); 
					$lexer->EOL();
				} 
				else throw new LogicException("NO LEXER SET");

				$this->line = '';
			}
			else $this->line .= $char; 
		}
	}


	public function DecodeFile(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : dict<string, nonnull> { 

		$this->lexer = new Lexer($this); 
		$this->parsers->add(new parserRoot($this));

		$file = \fopen($filename, "r", $use_include_path, $context);
		if($file === FALSE) throw new \Exception("FILE NOT FOUND");

		while(! \feof($file)) { 
			$this->parseBuffer(\fread($file, 1024));
		}

		if($lexer = $this->lexer) 
		{ 
			if(!\ctype_space($this->line)) $lexer->handleLine($this->line, $this->lineNum); 
			$lexer->EOF();
		}
		else throw new LogicException("NO LEXER SET"); 
		

		// assuming first parser is parserRoot, which it should always be 
		$root = ($this->parsers)[0] as parserRoot;
		return $root->getDict();
	}

	//TODO: Decode string 
}


// Main func
function decodeFile(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : dict<string, nonnull> { 
	return (new Decoder())->DecodeFile($filename, $use_include_path, $context);
}