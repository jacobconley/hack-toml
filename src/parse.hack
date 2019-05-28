namespace toml;

enum tokenType : int { 
	BARE_IDENT 			= 0;
	STRING 				= 1;
	STRING_MULTILINE	= 2;

	INTEGER				= 10;
	FLOAT 				= 11;

	BOOL				= 20;
	DATETIME			= 21;

	OP_DOT				= 40;
	OP_EQUALS			= 41; 
	OP_PUNCTUATION 		= 42; 
}

class token { 
}

class Decoder { 

	private vec<

}