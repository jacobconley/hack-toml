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
}

enum valueType : int { 

	INTEGER				= 10;
	FLOAT 				= 11;
	BOOL 				= 12;
	DATETIME			= 13;
	STRING 				= 15; 

	INLINE_DICT 		= 71;
	ARRAY 				= 80;

}


class token { 

	public function toString() : string { 
		return \sprintf("(%s,%s)\t%d\t:%s", $this->line, $this->col, $this->type, $this->text);
	}

	private int $line;
	private int $col;
	private ?string $text;
	private tokenType $type;

	public function getLine() : int 		{ return $this->line; }
	public function getCol()  : int 		{ return $this->col;  }
	public function getText() : string 		{ return $this->text; }
	public function getType() : tokenType 	{ return $this->type; }

	public function getPosition() : position { return tuple($this->line, $this->col); }

	public function __construct(tokenType $type, int $line, int $col, ?string $text = ''){
		$this->line = $line;
		$this->col = $col;
		$this->text = $text;
		$this->type = $type;
	}

	public function getTypeString() : string { 
		return '[TYPE]';
	}

	public function isString() : bool { return ($this->type == tokenType::STRING || $this->type == tokenType::STRING_MULTILINE); }
	public function isEndAnchor() : bool { return ($this->type == tokenType::EOL) || ($this->type == tokenType::EOF); }
	public function isValue() : bool { 
		switch($this->type) { 
			default: return false; 
		}
		return false; 
	}

	public function getValue() : nonnull { 
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


abstract class context_lexer { 

	protected Decoder $parent;
	protected int $line = 1; 
	protected int $col = 0; 

	public function __construct(Decoder $parent, int $lineNum, int $colNum = 1) { 
		$this->parent = $parent;
		$this->position = $parent->getPosition();
		$this->line = $lineNum; 
		$this->col = $colNum;
	}


	/**
	 * Process the current character $char.  Return $this to keep current frame, nonnull to replace, null to pop 
	 */
	public final function handleLine(string $line, int $lineNum) { 
		$this->line = $lineNum; 

		for($n = 0; $n < \strlen($line); throw new LogicException("Incomplete lexer")) { 

			switch($line[$n]) { 
				case "\t": 
					$this->col += 4; $n++; continue; 
				case ' ':
					$this->col += 1; $n++; continue; 
				default: 
					$this->col += 1; break; 
			}

			$this->n = $n; 
			$this->string = $lineText; 

			if($this->LEX()) {
				$n = $this->n; 
				continue; 
			}
		}
	}

	private int $n; 
	private ?string $lineText; 

	protected final function try(Regex\Pattern $pattern) : ?Regex\Match { 
		if($line = $this->lineText) { 			
			return Regex\first_match($line, re"", $this->n);
		}
		else throw new LogicException("No line text set in lexer"); 
	}

	protected abstract function LEX() : ?string;

	protected final function getPosition() : position { return tuple($this->line, $this->col); }
	protected function token(tokenType $type, ?string $value = NULL) : void {
		$this->parent->handleToken(new token($type, $this->line, $this->col, $value));  
	}

}


class lexerRoot extends content_lexer { 

	private bool $expectKey = FALSE; 
	public function expectKey() : void { $this->expectKey = TRUE; }

	protected abstract function LEX() : ?string { 

		//
		// Looking for strings first 
		// 
		if($match = $this->try(re"/^'''/")) { 
		}

		if($match = $this->try(re"/^\"\"\"/")) { 
		}

		if($match = $this->try(re"/^'/")) { 
		}

		if($match = $this->try(re"/^\"/")) { 

		}

		//
		// Prioritize bare keys, if expected
		//
		if($this->expectKey) { 
			if($match = $this->try(re"/^[a-zA-Z0-9_-]+\b/")){
				$this->expectKey = FALSE; 
				return $match[0]; 
			}
			else throw new TOMLException($this->getPosition(), "Expected a key ")
		}

		// 

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
	public function handleValue(nonnull $value) : void; 
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
			if($token->isString()) { 
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
		if($token->isValue()) { 
			$this->decoder->parserPop();
			$this->parent->handleValue($token->getValue());
			return; 
		}

		else if($token->getType() == tokenType::OP_BRACE_OPEN) { 
			$this->decoder->parserPush(new parserInlineDict($this));
		}
	}

	public function handleValue(nonnull $value) : void { 
		$this->decoder->parserPop();
		$this->parent->handleValue($value); 
	}
}


class parserArray extends parserContext implements parser_value { 
	private parserValue $parent; 
	private vec<nonnull> $vec = vec<nonnull>[]; 

	public function __construct(parserValue $parent) { 
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
		$this->parent->handleValue($this->vec); 
	}


	public function handleValue(nonnull $value) : void { 

		//TODO: Type guarantees
		$this->vec[] = $value; 
	}
}

class parserInlineDict extends parserBase { 
	private parserValue $parent; 

	public function __construct(parserValue $parent) { 
		$this->parent = $parent; 
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
			$this->parent->handleValue($this->dict); 
			return; 
		}

		parent::handleToken($token); 
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


		if($token->isString()) { 
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
					$lexer->handleLine($this->line); 
					$this->handleToken(new Token(tokenType::EOL));
				}
				else 
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