namespace toml;

use \LogicException;
use \HH\Lib\{ Str, Regex, Vec, Dict }; 

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

			case tokenType::OP_BRACKET_OPEN:		return "Opening bracket ( [ )";
			case tokenType::OP_BRACKET_CLOSE: 		return "Closing bracket ( ] )";
			case tokenType::OP_DB_BRACKET_OPEN:		return "Opening double bracket ( [[ )";
			case tokenType::OP_DB_BRACKET_CLOSE:	return "Closing double bracket ( ]] )";
			case tokenType::OP_BRACE_OPEN:			return "Opening brace ( { )";
			case tokenType::OP_BRACE_CLOSE:			return "Closing brace ( } )";

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

			// Special float values override before going into the main script;
			if($type == valueType::FLOAT) { 				
				switch($this->text) { 
					case "inf":
					case "+inf":
						return (float) 'INF';

					case "-inf":
						return (float) '-INF';

					case "nan":
					case "+nan":
					case "-nan":
						return (float) 'NAN';

					default: break; 
				}
			}


			switch($type) {

				case valueType::INTEGER: 
					$text = $this->text;		
					$text =	Str\replace($text, '_', ''); 		// Idk if PHP handles underscores, docs are shit 
					$text = Str\replace($text, '0o', '0'); 		// Since the validity was guaranteed earlier, the only 0o could be at the beginning
																// intval() uses a leading 0 to mean it's octal 

					return \intval($text);

				case valueType::FLOAT: 	
					$text = $this->text;
					$text =	Str\replace($text, '_', ''); 		
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
	protected int $lineNum = 1; 

	public function __construct(Decoder $parent) { 
		$this->parent = $parent;
	}


	// 
	// Helper functions
	//

	protected final function getPosition() : position { return tuple($this->lineNum, $this->n + 1); }
	public final function getLineNum() : int { return $this->lineNum; }
	public final function getParent() : Decoder { return $this->parent; }

	private function token(tokenType $type, string $value) : void {
		$this->parent->handleToken(new Token($type, $this->lineNum, $this->n, $value));  
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
		$this->parent->handleToken(new Token(tokenType::EOL, $this->lineNum, 0));
	}

	public final function EOF() : void { 
		if($this->StringHandler) throw new TOMLException(NULL, "Unexpected end-of-file in string literal");
		$this->parent->handleToken(new Token(tokenType::EOF, $this->lineNum, 0));
	}



	/**
	 * Process the current character $char.  Return $this to keep current frame, nonnull to replace, null to pop 
	 */
	public final function handleLine(string $line, int $lineNum, int $offset = 0) : void { 

		$this->lineNum 	= $lineNum; 
		// $this->lineText = $line; 
		$this->n 		= $offset; 

		while($this->n < \strlen($line)) { 
			$n = $this->n; 
			$this->lineText = Str\slice($line, $n); 

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

			// /* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			// if($match = $this->is('[[')) { $this->token(tokenType::OP_DB_BRACKET_OPEN, $match); 	continue; }
			// /* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			// if($match = $this->is(']]')) { $this->token(tokenType::OP_DB_BRACKET_CLOSE, $match); 	continue; }
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
			if($match = Regex\first_match($this->lineText, re"/^\d{4}-\d\d-\d\d((T| )\d\d:\d\d:\d\d(\.\d+)?)?(Z|((\+|-)\d\d:\d\d))?/")) { 
				$this->token(tokenType::DATETIME, $match[0]); 	
				continue; 
			}
			if($match = Regex\first_match($this->lineText, re"/^\d\d:\d\d:\d\d(\.\d+)?/")) { 
				$this->token(tokenType::DATETIME, $match[0]); 	
				continue; 
			}

			// Number
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = Regex\first_match($this->lineText, re"/^0x[0-9a-f_]+|^0o[0-7_]|^0b[01_]|^[\+-]?((inf|nan)|[0-9_]+(\.[0-9_]+)?([eE][\+-]?[0-9_]+)?)/")) 
			{ 				
				// Some funky tests we had to do in able to simplify the above regex
				// I tried to do it with one big regex, didn't quite work out
				// I'm sure it's possible but I'll deal with it later
				// Or you can, kind reader! 
				$slice = Str\slice($match[0], 0, 2);
				if($match[0][0] === '0' 
					&& $slice !== '0o' 
					&& $slice !== '0x'
					&& $slice !== '0b'
					&& \count($match) == 1) throw new TOMLException($this->getPosition(), "Leading zeros are not allowed");
				//TODO: Test for double underscores

				if(!(Str\is_empty($match[2]) && Str\is_empty($match[3]) && Str\is_empty($match[4]))) 			$this->token(tokenType::FLOAT, $match[0]); 
				else 													$this->token(tokenType::INTEGER, $match[0]); 

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
			// This code is kinda spaghetti, my bad
			if($char == '\\' && !($this->literal)) { 
				$loc = tuple($lineNum, $i + 1);
				$escr = $line[$i + 1]; 

				// Crudely migrated this from the switch statement
				// No idea why that didn't work... I thought string switches worked in hack ? 
				if($escr == '\\') {
					$this->value .= '\\';  	$i++; continue; 
				}
				else if($escr == 'b') { 
					$this->value .= "\x08"; $i++; continue;
				}
				else if($escr == 't') {
					$this->value .= "\t";  	$i++; continue; 
				}
				else if($escr == 'n') {
					$this->value .= "\n";  	$i++; continue; 
				}
				else if($escr == 'f') {
					$this->value .= "\f";  	$i++; continue; 
				}
				else if($escr == 'r') {
					$this->value .= "\r";  	$i++; continue; 
				}
				else if($escr == '"') {
					$this->value .= '"';   	$i++; continue; 
				}

				else if($escr == "u" || $escr == "U") {
					if($match = Regex\first_match($line, re"/U[a-fA-F0-9]{8}|u[a-fA-F0-9]{4}/", $i + 1)) { 
						// Unicode encoding
						$len = ($escr == 'u' ? 4 : 8);
						$i += $len + 1;

						$this->value .= \pack('H*', Str\slice($match[0], 1));
						continue;
					}
					else throw new TOMLException($loc, "Incomplete unicode escape sequence");
				}
					 
				else throw new TOMLException($loc, "Unrecognized escape character '".$escr."'"); 
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
			//if(\array_key_exists($key[0], $dict)) throw new TOMLException($keyToken->getPosition(), \sprintf('Duplicate key "%s"', $this->keystr($key))); 
			$name = $key[0];
			$obj = idx($dict, $name, dict<string,nonnull>[]);  

			/* HH_IGNORE_ERROR[4101] Generics */
			if(!($obj is dict)) throw new TOMLException($keyToken->getPosition(), \sprintf("Duplicate key '%s'", $key[$count - 1]));

			/* HH_IGNORE_ERROR[4101] Generics */
			if($value is dict)	$dict[$name] = Dict\merge($obj, $value); 
			else 				$dict[$name] = $value; 
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
			if($token = $this->keyToken) { 
				// /* HH_IGNORE_ERROR[4101] Generics */
				// $this->decoder->getRootParser()->defineKey($key, $token, $value is dict);
				$this->_addKV($key, $token, $value, inout $dict); 
			}
		}
		else throw new LogicException("Handling value without key");

		$this->dict 	= $dict; 
		$this->key 		= NULL;
		$this->keyToken = NULL;
	}
	public function appendKeyValue(dict<string, nonnull> $value) : void 	{ 
		$dict = $this->dict; 
		if($key = $this->key) {
		 	if($token = $this->keyToken) {
				/* HH_IGNORE_ERROR[4101] Generics */
				// $this->decoder->getRootParser()->defineKey($key, $token, $value is dict, FALSE);
		 		$this->_appendKV($key, $token, $value, inout $dict); 
		 	}
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
	public function handleKey(vec<string> $key, Token $token) : void 
	{ 
		if($this->key is nonnull) throw new LogicException("A key has been handled and not cleared"); 
		$this->key = $key; 
		$this->keyToken = $token;
	}

	public function getKey() : ?vec<string> { return $this->key; }

	public function handleValue(Token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void { 
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



// Quick bullshit key-definition class I wrote 
class keydefn { 
	public bool $defined = FALSE; 				// Has the key been DIRECTLY defined?
	public ?dict<string, keydefn> $children; 	// Children of the key 

	public function __construct(bool $defined, ?dict<string, keydefn> $children = NULL) { 
		$this->defined = $defined;
		$this->children = $children; 
	}
}


//
// The special instance of the parser that is at the bottom of the stack 
//
class parserRoot extends parserBase { 


	public function __construct(Decoder $decoder) {
		parent::__construct($decoder);
	}

	private dict<string, keydefn> $definitions = dict<string, keydefn>[];

	private function _defineKey(vec<string> $key, Token $keyToken, inout dict<string, keydefn> $defns, bool $asDict) : void { 
		$count = \count($key); 
		if($count == 0) throw new LogicException("Empty key in definition");

		else if($count == 1) {
			$name = $key[0];

			// The key has already been defined, explicitly or otherwise
			if(\array_key_exists($name, $defns)) {
				$def = $defns[$name]; 

				// It is explicitly redefined.  Error
				if($def->defined) throw new TOMLException($keyToken->getPosition(), \sprintf("Duplicate key '%s'", $name));

				// This probably isn't strictly necessary... 
				if($asDict && $def->children is null) throw new LogicException("Making an implicit dict explicit which has no children");

				// It was implicitly defined before and is now made explicit.
				$def->defined = TRUE;
				$defns[$name] = $def; 
			}

			// It is now being defined explicitly
			else $defns[$name] = new keydefn(TRUE, $asDict ? dict<string, keydefn>[] : NULL);
		}

		else { 
			// We're in an intermediate, implicit dict
			$name = $key[0];  
			$slice = Vec\slice($key, 1);

			// If it has been implicitly defined, exit
			if(\array_key_exists($name, $defns)) { 
				$def = $defns[$name];
 
				$newmap = $def->children;
				if($newmap is nonnull) $this->_defineKey($slice, $keyToken, inout $newmap, $asDict); 
				else throw new LogicException("Defining children of an entry which has no child dict");
				$def->children = $newmap;
				$defns[$name] = $def; 
			}

			else { 
				$newmap = dict<string, keydefn>[]; 
				$this->_defineKey($slice, $keyToken, inout $newmap, $asDict); 
				$defns[$name] = new keydefn(FALSE, $newmap); 	 
			}
		}
	}

	// Makes sure that a given key hasn't already been directly defined before insertion within a higher-level parser
	// Throws a TOMLException on failure
	// $dict: If TRUE, the top level definition is a dict
	// $top: If TRUE, search all levels of the key, if FALSE, ignore the top level.  FALSE is used for appending in array-of-tables
	public function defineKey(vec<string> $key, Token $keyToken, bool $asDict = FALSE, bool $top = TRUE) : void { 
		$defns = $this->definitions;
		$this->_defineKey($top ? $key : Vec\take($key, \count($key) - 1),    $keyToken, inout $defns, $asDict); 
		$this->definitions = $defns;
	}




	public function addKeyValue(nonnull $value) : void { 
		if($key = $this->key) {
			if($token = $this->keyToken) { 
				/* HH_IGNORE_ERROR[4101] Generics */
				$this->defineKey($key, $token, $value is dict);
				parent::addKeyValue($value); 
			}
			else throw new LogicException("No key token");
		}
		else throw new LogicException("No key in addKeyValue");
	}



	public function handleToken(Token $token) : void { 

		switch($token->getType()) { 

			case tokenType::OP_BRACKET_OPEN:
				$block = new parserDictBody($this);
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
		if($this->expectKey) 
		{ 
			if($token->isKey()) { 
				if($token->getType() == tokenType::FLOAT) { 
					// A funky conditional I had to add because of how I designed this parser (poorly)
					// This could have been more elegant by desigining the lexer as a token stream - discussed in the readme
					foreach(\explode('.', $token->getText()) as $x) $this->keys[] = $x; 
				}
				else $this->keys[] = $token->getText(); 
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

			// If there's another opening bracket, it's an array-of-dicts
			if($token->getType() == tokenType::OP_BRACKET_OPEN) { 
				$this->parent->decoder->parserPop();
				$this->parent->decoder->parserPush(new parserDictArrayBody($this->parent));
				return; 
			}

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
					$this->expectLineEnd = TRUE;
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
	private bool $finishingOpen = FALSE; // Expecting second closing bracket ( ] ) 

	public function handleToken(Token $token) : void 
	{

		if($this->opened)
		{
			// End of the dictionary 
			if($token->getType() == tokenType::OP_BRACKET_OPEN || $token->getType() == tokenType::EOF) 
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

			if($this->finishingOpen && $token->getType() != tokenType::OP_BRACKET_CLOSE) throw new TOMLException($token->getPosition(), "Expected a double bracket ( ]] ) to finish declaring this table"); 


			if($token->getType() == tokenType::OP_BRACKET_CLOSE) {

				// A quick fix for when I had to remove the double bracket lex tokens
				if(!($this->finishingOpen)) { 
					$this->finishingOpen = TRUE;
					return; 
				}

				if($key = $this->key) { 
					$this->parent->handleKey($key, $token);
					$this->key 		= NULL;
					$this->opened 	= TRUE;
					$this->expectLineEnd = TRUE; 
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
	public function getRootParser() : parserRoot { 
		return $this->parsers[0] as parserRoot;
	}

	public function getLexer() : Lexer { 
		if($lexer = $this->lexer) return $lexer;
		else throw new LogicException("NO LEXER SET");
	} 

	public function handleToken(Token $token) : void { 

		if($p = $this->parsers->lastValue()) { 
			$p->handleToken($token); 
		}
		else throw new LogicException("No parsers on the stack"); 
	}

	public function parserPush(parserContext $parser) : void { 
		$this->parsers->add($parser); 
	}
	public function parserPop() : void { 
		$this->parsers->pop(); 
	}


	private int $lineNum = 0;
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


	public function DecodeStream(resource $file) : dict<string, nonnull> { 

		$this->lexer = new Lexer($this); 
		$this->parsers->add(new parserRoot($this));


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
