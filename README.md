![GitHub release (latest by date)](https://img.shields.io/github/v/release/jacobconley/hack-toml)

hack-toml
====

This small package provides an interface for reading [TOML](https://github.com/toml-lang/toml) files.  


Usage
====

All TOML decoders return a `DictAccess` object (see below).  Canonically, a TOML document is an unordered list of key/value pairs. 

The following methods parse TOML:

- `toml\parse(string $toml)` - Decodes a string of TOML
- `toml\parseFile(string $path, bool $use_include_path = FALSE, ?resource context = NULL)` - Decodes a file - the arguments in this method are passed directly to `fopen`

A stream object can also be decoded directly if needed by using `(new toml\Decoder())->DecodeStream(...)`.  


DictAccess object
-----

In light of the HHVM team's [stance on the legacy PHP array object](https://hhvm.com/blog/10649/improving-arrays-in-hack) and the fact that PHP compatibility is long gone, I opted to create the `DictAccess` object instead of the legacy type.  For version 1.0 a `dict<string,nonnull>` was used, but type safety for this proved too cumbersome in strict hack. This also makes sense for security as TOML is largely designed to be a configuration format and the developer using this package should know at all times what the keys and data types are that they're reading.  

The `DictAccess` object  wraps around the `dict<string, nonnull>` object, providing the below methods:

Type-agnostic methods:

- `->exists(string $key) : bool` - Returns true if the given key has a value 
- `->get(string $key) : nonnull` - Accesses the wrapped dictionary straight-up; equivalent to using the array access operator (`[$name]`)

Type-safe methods: 

- `->int(string $key) : int`, etc - Returns the value at $key as the appropriate type, and throws an exception if the value is unset or the wrong type
- `->intlist(string $key) : vec<int>`, etc - Returns a vec corresponding to the given key.  Like the above, but with a vec
- `->_int(string $key) : ?int` - Returns the value if it exists, or `NULL` otherwise 
- `->_intlist(string $key) : ?vec<int>` - Returns the vec if it exists, or `NULL` otherwise

The `int` in the above methods can also be replaced with any of the following types: `string`, `float`, `bool`, `datetime`, `dict`.  e.g `->bool($key) : bool`, `->_floatlist($key) : ?vec<float>`

For the optional methods, the null coalescing operator can be used to provide a default value, e.g. `$somedict->_int('somekey') ?? 42`

`datetime` is represented by a [PHP `DateTime` object](https://www.php.net/manual/en/class.datetime.php), and `dict` corresponds to another `DictAccess` object.  



Testing
===

This project is tested primarily with [BurntSushi's test suite](https://github.com/BurntSushi/toml-test).  The project is amazing and crucial to verifying this one - but we nonetheless had some issues with tests that came out as false negatives.  Instead of including the test suite as a submodule, I just cloned it in `tests/burntsushi/` - as of today (16 September, 2019) the test suite hasn't been updated in 9 months, so this should not be an issue in the short term.  

Tests that I've determined to be a false negative were archived into the `tests/burntsushi/false-negative/` directory. For the 1.0 release I've verified each of these cases manually, but new tests for each of these cases should be remade in Hack language.  This will all need to be integrated into CI.  This is all addressed by issue #1, which must be resolved before any work continues after this version.  


Issues
===

This version of the parser is not fully compliant as it interprets some technically-invalid TOML without reporting errors.  Examples of this include integers with leading zeros or table declarations with space inside of the braces.  These small errors were easy to see past with the structure of the lexer and parser, but will nonetheless be resolved very soon - this is issue #2.  


About this project
====

I wrote this on a whim after discovering TOML and realizing Hack didn't have one - I plan on using it a lot now, since TOML is neat.  However, it was my first parser, and I wrote it blindly as a sort of way to test myself. It was a fun experiment and I was able to pull it off, but the code is rather messy, and deserves to be cleaned up.  The lexer needs to be reimlemented as a token stream that is invoked by the parser stack, and that alone will make the code a lot neater.  I may have to do this before addressing the issues above.  

I also of course want to make a serializer for this project as well.  

If you're interested in this project, feel free to reach out to me at jake@jakeconley.com or just fork & pull request.  
