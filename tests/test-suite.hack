#!/usr/bin/hhvm

require_once __DIR__."/../vendor/hh_autoload.hh";
include __DIR__.'/../src/parse.hack'; 

use \HH\Lib\{ Vec, Dict };

function testsuite_val(mixed $val) : ?dict<string,string> { 		
	if($val is string) { 
		return dict<string,string>[ 'type' => 'string', 'value' => $val ];
	}

	if($val is int) { 
		return dict<string,string>[ 'type' => 'integer', 'value' => strval($val) ];
	}

	if($val is float){ 
		return dict<string,string>[ 'type' => 'float', 'value' => strval($val) ];
	}

	if($val is DateTime) { 
		return dict<string,string>[ 'type' => 'datetime', 'value' => $val->format(DateTime::RFC3339) ];
	}

	if($val is bool) { 
		return dict<string,string>[ 
			'type' => 'bool', 
			'value' => $val ? 'true' : 'false'
		];
	}

	return NULL;
}

function testsuite_array(vec<nonnull> $vec) : vec<nonnull> { 
	return Vec\map($vec, function(nonnull $val){ 
		if($y = testsuite_val($val))	return $y;
		/* HH_IGNORE_ERROR[4101] Generics */
		/* HH_IGNORE_ERROR[4110] Generics */
		else if($val is vec) 			return testsuite_array($val); 
		/* HH_IGNORE_ERROR[4101] Generics */
		/* HH_IGNORE_ERROR[4110] Generics */
		else if($val is dict) 			return testsuite_recur($val); 
		else throw new LogicException("Unhandled type");
	});
}

function testsuite_recur(dict<string, nonnull> $dict) : dict<string, nonnull> { 
	return Dict\map($dict, function(nonnull $val){

		if($res = testsuite_val($val)) 	return $res; 
		/* HH_IGNORE_ERROR[4101] Generics */
		/* HH_IGNORE_ERROR[4110] Generics */
		if($val is dict) 				return testsuite_recur($val); 
		/* HH_IGNORE_ERROR[4101] Generics */
		if($val is vec) {
		/* HH_IGNORE_ERROR[4110] Generics */
			return dict<string, nonnull>[ 'type' => 'array', 'value' => testsuite_array($val) ]; 
		}

		throw new LogicException("Unhandled type"); 

	});
}

<<__EntryPoint>>
function testsuite_main() : noreturn { 
	try { 
		echo(json_encode(testsuite_recur((new toml\Decoder())->DecodeStream(STDIN))));
		exit(0);
	}
	catch(toml\TOMLException $e) { 
		exit(1); // Exiting with an actual TOML error
	}
	catch(Exception $e) { 
		exit(0); // Exiting with a decoder error - this should fail the tester
	}
}