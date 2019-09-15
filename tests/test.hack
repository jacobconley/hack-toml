#!/usr/bin/hhvm

require_once __DIR__."/../vendor/hh_autoload.hh";
include __DIR__.'/../src/parse.hack'; 

use toml\{ Decoder, token, TOMLException };

<<__EntryPoint>>
function main() : noreturn { 


	try { 
		$time = \microtime(TRUE);
		$result = toml_decode_file(__DIR__.'/test.toml');

		\printf("Done in %d ms\n", \microtime(TRUE) - $time);
		echo " -- Result -- \n";
		print_r($result); 
	}
	catch (TOMLException $e) {
		printf("\nTOML Error:    %s\n\n", $e->getMessage());
		printf("%s:%s\n", $e->getFile(), $e->getLine());
		echo $e->getTraceAsString()."\n";
	}
	catch (Exception $e) {
		echo 'Exception!    ';
		echo $e->getMessage()."\n";
		printf("%s:%s\n", $e->getFile(), $e->getLine());
		echo $e->getTraceAsString()."\n";
	}

	exit(0);

}