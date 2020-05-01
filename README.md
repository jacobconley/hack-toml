![GitHub release (latest by date)](https://img.shields.io/github/v/release/jacobconley/hack-toml)

hack-toml
====

This small package provides an interface for reading [TOML](https://github.com/toml-lang/toml) files.  


Usage
====

All TOML decoders return a `dict<string, nonnull>`.  Canonically, a TOML document is an unordered list of key/value pairs. 

The following methods parse TOML:

- `toml\parse(string $toml)` - Decodes a string of TOML
- `toml\parseFile(string $path, bool $use_include_path = FALSE, ?resource context = NULL)` - Decodes a file - the arguments in this method are passed directly to `fopen`

A stream object can also be decoded directly if needed by using `(new toml\Decoder())->DecodeStream(...)`.  


Type Safety
====

One of the central features of the Hack language is the strong typing; this is a very necessary evil.  Meanwhile, Hack has been undergoing rapid development lately, and the new `dict` type is just the latest example of this.

Currently, the standard way to get a type-safe dictionary mapping from a `dict` like this is to use [type-assert](https://github.com/hhvm/type-assert) and [shapes](https://docs.hhvm.com/hack/built-in-types/shapes).

A shape can be passed as the generic argument to the `match<T>($dict)` functions in type-assert, as in the below example.  
Recall from the hhvm docs above that you can prepend the `?` operator to a shape key name to make that field optional, which is different from making its value optional.

```
type s1 = shape(
    'name'          => string,
    ?'nickname'     => string,
    'id'            => int
);

$dict = dict<string, mixed>[
    'name'          => 'john',
    id              => 32
];

$dict = TypeCoerce\match<s1>($dict)
```

which yields the below object with the appropiate type safety, which can be accessed just like a dict or old-school PHP array. 

```
    [name]  => john,
    [id]    => 32
```

Some other tips:
- `TypeAssert\matches` will attempt to convert the values strictly with regards to their type; `TypeCoerce\match` will attempt to perform type juggling (such as string-to-int conversions) 
- For now, I've been using `array_key_exists('key', $dict)` to test for a key's presence, but
- The null-coalescing operator `??` can be used to specify default values for keys that don't exist



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
