use toml\Decoder; 

function toml_decode(string $toml) : dict<string, nonnull> { 
	return (new Decoder())->DecodeString($toml); 
}

function toml_decode_file(string $filename, bool $use_include_path = FALSE, ?resource $context = NULL) : dict<string, nonnull> {
	$file = \fopen($filename, "r", $use_include_path, $context);
	if($file === FALSE) throw new \Exception("FILE NOT FOUND");
	return (new Decoder())->DecodeStream($file);  
}