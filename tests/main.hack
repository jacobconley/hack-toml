include __DIR__.'/../src/parse.hack'; 

use toml\{ Decoder, token, TOMLException };

<<__EntryPoint>>
function main() : noreturn { 

	$Decoder = new Decoder();

	// try { 
	// 	$result = $Decoder->DecodeFile(__DIR__.'/test.toml');
	// }
	// catch (TOMLException $e) {
	// 	printf("\nTOML Error:    %s\n", $e->getMessage());
	// }
	// catch (Exception $e) {
	// 	echo 'Exception!    ';
	// 	echo $e->getMessage()."\n";
	// 	echo $e->getTraceAsString()."\n";
	// }

	// echo "\n -- Tokens -- \n";

	// $tokens = $Decoder->getTokens(); 
	// foreach($tokens as $token) { printf("%s\n", $token->toString()); }

	exit(0);

}