namespace toml;
use \DictAccess;

function parse(string $toml) : DictAccess { 
	return new DictAccess((new Decoder())->DecodeString($toml)); 
}

function parseFile(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : DictAccess {
	$file = \fopen($filename, "r", $use_include_path, $context);
	if($file === FALSE) throw new \Exception("FILE NOT FOUND");
	return new DictAccess((new Decoder())->DecodeStream($file));
}