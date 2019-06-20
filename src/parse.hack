namespace toml;

require_once __DIR__."/../vendor/hh_autoload.hh";

use \LogicException;
use \HH\Lib\Str;
use \HH\Lib\Regex;

// TODO: Line position here
class TOMLException extends \Exception {
	public function __construct(position $position, string $message) { 
		parent::__construct('At '.positionString($position).': '.$message); 
	}
}
class TOMLUnexpectedException extends TOMLException { 
	public function __construct(token $token) {
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


class token { 

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
			case tokenType::KEY: 		return 'Key';
			case tokenType::INTEGER: 	return 'Integer';
			case tokenType::FLOAT: 		return 'Float';
			case tokenType::BOOL: 		return 'Boolean';
			case tokenType::DATETIME: 	return 'DateTime';
			case tokenType::STRING:		return 'String';

			case tokenType::EOL: 		return "end-of-line";
			case tokenType::EOF: 		return "end-of-file";
			case tokenType::COMMENT: 	return "Comment";

			case valueType::INLINE_DICT:return "Inline table";
			case valueType::ARRAY: 		return "Array";
			case valueType::EMPTY: 		return "Empty";
			default: 					return NULL;
		}
	}

	public function getTypeString() : string { return token::EnumToString((int) $this->type) ?? $this->text; }

	public function isEndAnchor() : bool { return ($this->type == tokenType::EOL) || ($this->type == tokenType::EOF); }

	public function getValueType() : ?valueType { 
		$int = (int) $this->type; 
		if($int >= 10 && $int < 20) return $int as valueType;
		else return NULL;
	}

	public function getValue() : nonnull { 
		if($this->getValueType() is null) throw new LogicException("This token is not a value type");

		switch($this->type) {

			case tokenType::INTEGER: 		
				$text =	Str\replace($this->text, '_', ''); 		// Idk if PHP handles underscores, docs are shit 
				$text = Str\replace($this->text, '0o', '0'); 	// Since the validity was guaranteed earlier, the only 0o could be at the beginning
																// intval() uses a leading 0 to mean it's octal 

				return \intval($text);

			case tokenType::FLOAT: 			
				$text =	Str\replace($this->text, '_', ''); 		
				return \doubleval($text);

			case tokenType::BOOL:
				if($this->text === "true") return TRUE;
				else return FALSE;


			case tokenType::STRING: 		return $this->text;
			case tokenType::DATETIME:		return new \DateTime($this->text);

			default:						throw new LogicException("Type not handled in value()");
		}
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

	protected final function getPosition() : position { return tuple($this->line, $this->n); }
	public final function getLineNum() : int { return $this->parent->getLineNum(); }
	public final function getParent() : Decoder { return $this->parent; }

	private function token(tokenType $type, string $value) : void {
		$this->parent->handleToken(new token($type, $this->line, $this->n, $value));  
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
		if(Str\starts_with($this->lineText, $str)) { 
			$this->n += Str\length($str); 
			return $str;
		} 
		else return NULL;
	}

	//
	// Lexing
	//


	private bool $expectKey = FALSE; 
	public function expectKey() : void { $this->expectKey = TRUE; }

	// Helper functions for String Handler
	public function isExpectingKey() : bool { return $this->expectKey; }
	public function handleStringKey(string $value) : void { 
		$this->expectKey = FALSE; 
		$this->token(tokenType::KEY, $value);
	}


	private int $n = 0;
	private string $lineText = '';  // dummy init value 

	private ?StringHandler $StringHandler; 

	/**
	 * Process the current character $char.  Return $this to keep current frame, nonnull to replace, null to pop 
	 */
	public final function handleLine(string $line, int $lineNum, int $offset = 0) : void { 
		$this->line 	= $lineNum; 
		$this->lineText = $line; 

		for($n = $offset; $n < \strlen($line); $this->n = $n) { 

			// First - see if there is a string context
			// If there is, it will return a new $n offset to skip to if it finishes, or NULL which means it continues into the next line as well
			if($handler = $this->StringHandler) { 
				if($newOffset = $handler->handleLine($line, $lineNum, $n)) { 
					// String is ending, its token has already been handled by the StringHandler so we advance to the new offset
					$this->StringHandler = NULL;
					$n = $newOffset; 
					continue;
				}
				else return; 
			}

			if(\ctype_space($line[$n])){ $n++; continue; }

			if($line[$n] == "#") { $this->token(tokenType::COMMENT, '#'); return;  }


			//
			// "Normal" lexing
			//

			//
			// Looking for strings first 
			// 

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('"""')) { 
				if($this->expectKey) throw new TOMLException($this->getPosition(), "Expected a key, cannot use a multi-line string");

				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
				continue;
			}

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is("'''")) { 
				if($this->expectKey) throw new TOMLException($this->getPosition(), "Expected a key, cannot use a multi-line string");

				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
				continue;
			}

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('"')) {
				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
				continue;
			}

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is("'")) { 
				$this->StringHandler = new StringHandler($this, $this->getPosition(), $match);
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
			// Prioritize bare keys, if expected
			//
			if($this->expectKey) { 
				if($match = Regex\first_match($line, re"/^[a-zA-Z0-9_-]+\b/", $n))
				{
					$this->expectKey = FALSE; 
					$this->token(tokenType::KEY, $match[0]);
					continue; 
				}
				else throw new TOMLException($this->getPosition(), "Expected a key here");
			}

			//
			// Value types 
			// 

			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('true')) 	{ $this->token(tokenType::BOOL, $match); 	continue; }
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = $this->is('false')) { $this->token(tokenType::BOOL, $match); 	continue; }

			// Datetime 
			if($match = Regex\first_match($line, re"/^\d{4}-\d\d-\d\d(T| )\d\d:\d\d:\d\d(\.\d+)?(Z|((\+|-)\d\d:\d\d))?/", $n)) { 
				$this->token(tokenType::DATETIME, $match[0]); 		
				continue; 
			}

			// Number
			/* HH_IGNORE_ERROR[4276] $match will never be a falsy value */
			if($match = Regex\first_match($line, re"/0x[0-9a-f_]+|0o[0-7_]|0b[01_]|[\+-]?(inf|nan|(0|[1-9]([0-9_])*(\.[0-9_]+)?)([eE][\+-]?[0-9_]+)?)/", $n)) { 
				if(!(Str\is_empty($match[4]) && Str\is_empty($match[5])) || Str\starts_with($match[0], '0')) 	$this->token(tokenType::FLOAT, $match[0]); 
				else 																							$this->token(tokenType::INTEGER, $match[0]); 
			}

			throw new TOMLException($this->getPosition(), "Unrecognized input");
		}
	}
}


class StringHandler { 
	private Lexer $parent; 

	private string $value = ""; 
	private position $pos; 

	private string $delim; 
	private bool $literal, $multiline; 

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


	private bool $trimmingWS = FALSE; 
	public function trimWS() : void { $this->trimmingWS = TRUE; }

	// Returns NULL if string is still going, or offset if it ends
	
	public final function handleLine(string $line, int $lineNum, int $offset) : ?int
	{ 
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


		// Newline immediately following opening multiline delim, ignored and continued 
		if($this->multiline && Str\is_empty($line)) return NULL; 

		for($i = $offset; $i < Str\length($line); $i++) { 
			$char = $line[$i];

			// Escape sequence
			if($char == '\\' && !($this->literal)) { 
				if($match = Regex\first_match($line, re"/^\\(U[a-fA-F0-9]{8}|u[a-fA-F0-9]{4}|.)/", $i + 1)) { 

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

				$len = 1; 
				if($this->multiline) 
				{ 
					$len = 3; 

					// Incomplete closer
					if(Str\slice($line, $len) != $this->delim) { 
						$this->value .= $char; 
						continue; 
					}
				}

				else { 
					if($this->parent->isExpectingKey()) $this->parent->handleStringKey($this->value); 
					else $this->parent->getParent->handleToken(new token(
						tokenType::STRING,
						$this->pos[0], $this->pos[1],
						$this->value
					));
					return $offset + $len;
				}
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

	public abstract function handleToken(token $token) : void;

	protected function pop() : void { $this->decoder->parserPop(); }
}


interface parser_value {
	require extends parserContext;
	public function handleValue(token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void; 
}


//
// Phrase parsing
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

	private bool $dotting = FALSE; 

	public function handleToken(token $token) : void 
	{ 
		if($this->dotting) 
		{ 
			if($token->getType() == tokenType::KEY) { 
				$this->keys[] = $token->getText(); 
				$this->dotting = FALSE;
			}
			else throw new TOMLException($token->getPosition(), "Expected a key following the dot (.)"); 
		}

		else if($token->getType() == tokenType::OP_DOT) { 
			$this->dotting = TRUE;
			return; 
		}

		else { 
			$this->pop();
			$this->parent->handleKey($this->keys); 
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

	public function handleToken(token $token) : void { 
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

		else throw new TOMLException($token->getPosition(), "Expected a value type here"); 
	}

	public function handleValue(token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void { 
		$this->decoder->parserPop();
		$this->parent->handleValue($token, $value, $type, $subtype); 
	}
}


class parserArray extends parserContext implements parser_value { 
	private parserValue $parent; 
	private vec<nonnull> $vec = vec<nonnull>[]; 
	private ?valueType $subtype; 
	private token $init; 

	public function __construct(parserValue $parent, token $init) { 
		$this->parent = $parent; 
		parent::__construct($parent->decoder);

		$this->decoder->parserPush(new parserValue($this)); 
	}

	public function handleToken(token $token) : void {
		if($token->isEndAnchor()) return; // Ignore newlines in array 

		if($token->getType() == tokenType::OP_COMMA) { 
			$this->decoder->parserPush(new parserValue($this)); 
			return; 
		}

		$this->decoder->parserPop();
		$this->parent->handleValue($this->init, $this->vec, valueType::ARRAY, $this->subtype ?? valueType::EMPTY); 
	}


	public function handleValue(token $token, nonnull $value, valueType $type, ?valueType $subtype = NULL) : void { 

		if($this->subtype != NULL && $x != $this->subtype) throw new TOMLException($token->getPosition(), \sprintf('Member of type %s in array previously of type %s', Token::EnumToString($type) ?? '-', Token::EnumToString($type) ?? '-'));
		else $this->subtype = $type; 
		
		$this->vec[] = $value; 
	}
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

	private function topDict(vec<string> $key) : dict<string, nonnull> {
		$x = $this->dict;

		// Resolving nested keys - so that $x will be the intermost dict if the array is nested
		$count = \count($key); 
		if($count == 0) throw new LogicException("Empty key"); 
		else if($count > 1) {
			for($i = 0; $i < \count($key) - 1; $i++) { 
				/* HH_FIXME[4110] No idea why nonnull is incompatible with nonnull */
				$x = \idx($x, $key[$i], dict<string, nonnull>[]); 
			} 
		}

		return $x; 
	}
	private function topKey(vec<string> $key) : string { 
		$count = \count($key); 
		if($count == 0) throw new LogicException("Empty key");
		else if ($count == 1) return $key[0];
		else return $key[$count - 2]; 
	}

	public function addKeyValue(vec<string> $key, mixed $value) : void 
	{ 
		$x = $this->topDict($key); 
		$x[$this->topKey($key)] = $value; 
	}
	public function appendKeyValue(vec<string> $key, dict<string, nonnull> $value) : void 
	{
		$vec = \idx($this->topDict($key), $this->topKey($key), vec<dict<string, nonnull>>[]);
		/* HH_IGNORE_ERROR[4101] */
		if($vec is vec) $vec[] = $value; 
		else throw new LogicException("Appending to a non-array in appendKeyValue");
	}

	//
	// Parser context
	//

	protected ?vec<string> $key;
	public function handleKey(vec<string> $key) : void { 
		if($this->key is nonnull) throw new LogicException("A key has been handled and not cleared"); 
		$this->key = $key; 
	}

	public function handleValue(nonnull $value) : void { 
		if($key = $this->key) { 
			$this->addKeyValue($key, $value); 
			$this->expectLineEnd = TRUE; 
		}
		else throw new LogicException("Handling value with no key"); 
	}

	protected bool $expectEquals = FALSE; 
	protected bool $expectLineEnd = FALSE; 


	//
	// Main method
	//

	public function handleToken(token $token) : void 
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
		if($this->expectEquals) { 
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


		if($token->getType() == tokenType::STRING) { 
			$kp = new parserKey($this);
			$kp->handleToken($token); 
			$this->decoder->parserPush($kp); 

			return;
		}

		else throw new TOMLUnexpectedException($token); 
	}
}

class parserRoot extends parserBase { 

	public function handleToken(token $token) : void { 
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

class parserInlineDict extends parserBase { 
	private parserValue $parent; 
	private token $init; 

	public function __construct(parserValue $parent, token $init) { 
		$this->parent = $parent; 
		$this->init = $init; 
		parent::__construct($parent->decoder);
	}


	public function handleToken(token $token) : void {

		if($this->expectLineEnd) {
			if($token->getType() == tokenType::OP_COMMA) { 
				$this->expectLineEnd = FALSE; 
				return; 
			}
			else throw new TOMLException($token->getPosition(), "Expected comma (,) to separate entries in inline table"); 
		}

		if($token->getType() == tokenType::OP_BRACE_CLOSE) { 
			$this->decoder->parserPop();
			$this->parent->handleValue($this->init, $this->dict, valueType::INLINE_DICT); 
			return; 
		}

		parent::handleToken($token); 
	}
}



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
	private ?vec<string> $dictKey;

	public function handleToken(token $token) : void 
	{
		// Gotta override this in two ways:
		// 1) Handling the declaration stage, when $this->opened is FALSE 
		// 2) Handling the end of this dictionary, at which point control should pass to the next context in the stack

		if($this->opened)
		{
			// End of the dictionary 
			if($token->getType() == tokenType::OP_BRACKET_OPEN || $token->getType() == tokenType::EOF) { 
				if($key = $this->dictKey) {
					$this->pop(); 
					$this->parent->addKeyValue($key, $this->dict); 
					$this->parent->handleToken($token); 
					return; 
				}
				else throw new LogicException("No key to add dict to");
			}

			// Calling the parent implementation here, as opposed to passing control to the parent context instance
			else parent::handleToken($token); 
		}
		else { 

			// Finishing up the declaration stage 
			if($token->getType() == tokenType::OP_BRACKET_CLOSE) {
				if($key = $this->key) { 
					$this->dictKey 	= $key;
					$this->key 		= NULL;
					$this->opened 	= TRUE; 
					return; 
				}
				else throw new TOMLException($token->getPosition(), "Expected a key in [dictionary] declaration"); 
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
	private ?vec<string> $dictKey;

	public function handleToken(token $token) : void 
	{

		if($this->opened)
		{
			// End of the dictionary 
			if($token->getType() == tokenType::OP_DB_BRACKET_OPEN || $token->getType() == tokenType::EOF) { 
				if($key = $this->dictKey) {
					$this->pop(); 
					$this->parent->appendKeyValue($key, $this->dict); 
					$this->parent->handleToken($token); 
					return; 
				} else throw new LogicException("No key to append dict array to");
			}

			else parent::handleToken($token); 
		}
		else { 

			// Finishing up the declaration stage 
			if($token->getType() == tokenType::OP_DB_BRACKET_CLOSE) {
				if($key = $this->key) { 
					$this->dictKey 	= $key;
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
	private ?context_lexer $lexer;
	private Vector<parserContext> $parsers = Vector<parserContext>{};


	public function handleToken(token $token) : void { 
		if($p = $this->parsers->lastValue()) $p->handleToken($token); 
		else throw new LogicException("No parsers on the stack"); 
	}

	public function parserPush(parserContext $parser) : void { $this->parsers->add($parser); }
	public function parserPop() : void { $this->parsers->pop(); }


	private int $lineNum = 1;
	public function getLineNum() : int { return $this->lineNum; }

	private string $line = "";
	private function parseBuffer(string $buf) : void { 

		for($i = 0; $i < Str\length($buf); $i++){

			$char = $buf[$i];

			if($char == "\r") continue; // Flat-out ignoring carriage returns, don't think this is a bad idea (?)

			if($lexer = $this->lexer) { 
				if($char == "\n") { 
					$this->lineNum++; 
					$lexer->handleLine($this->line, $this->lineNum); 
					$this->handleToken(new Token(tokenType::EOL));
				}
				else $this->line .= $char; 
			}
			else throw new LogicException("No lexer set");
		}
	}


	public function DecodeFile(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : dict<string, nonnull> { 
		$file = \fopen($filename, "r", $use_include_path, $context);
		if($file === FALSE) throw new \Exception("FILE NOT FOUND");

		while(! \feof($file)) { 
			$this->parseBuffer(\fread($file, 1024));
		}

		if($lexer = $this->lexer) $this->lexer->EOF(); 
		else throw new LogicException("No lexer set");

		return dict<string, nonnull>[ ];
	}

	//TODO: Decode string 
}


// Main func
function decodeFile(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : dict<string, nonnull> { 
	return (new Decoder())->DecodeFile($filename, $use_include_path, $context);
}