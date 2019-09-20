class DictAccessException extends Exception { 

	public static function DNE(string $name) : DictAccessException { 
		return new DictAccessException("Key $name does not exist");
	}

	public static function WrongType(string $name, string $expectedType) : DictAccessException { 
		return new DictAccessException("Value $name is not of type $expectedType");
	}

}

/**
 * This class wraps around a dict<string, nonnull> to provide convenient read-only type-safe access to a dictionary such as those output by the TOML reader. 
 */
class DictAccess { 

    private dict<string, nonnull> $dict;

	public function __construct(dict<string, nonnull> $dict) { 
		$this->dict	 = $dict; 
	}

    public function exists(string $offset) : bool { 
        return \array_key_exists($offset, $this->dict); 
    }

	public function get(string $offset) : nonnull { return $this->dict[$offset]; }


	//
	// Primitives
	//

    public function string(string $key) : string { 
		if(! \array_key_exists($key, $this->dict)) throw DictAccessException::DNE($key);
		$x = $this->dict[$key];
		if($x is string) return $x; 
		else throw DictAccessException::WrongType($key, 'string'); 
    }

    public function int(string $key) : int { 
		if(! \array_key_exists($key, $this->dict)) throw DictAccessException::DNE($key);
		$x = $this->dict[$key];
		if($x is int) return $x; 
		else throw DictAccessException::WrongType($key, 'int'); 
    }

    public function float(string $key) : float { 
		if(! \array_key_exists($key, $this->dict)) throw DictAccessException::DNE($key);
		$x = $this->dict[$key];
		if($x is float) return $x; 
		else throw DictAccessException::WrongType($key, 'float'); 
    }

    public function bool(string $key) : bool { 
		if(! \array_key_exists($key, $this->dict)) throw DictAccessException::DNE($key);
		$x = $this->dict[$key];
		if($x is bool) return $x; 
		else throw DictAccessException::WrongType($key, 'bool'); 
    }

    public function DateTime(string $key) : DateTime { 
		if(! \array_key_exists($key, $this->dict)) throw DictAccessException::DNE($key);
		$x = $this->dict[$key];
		if($x is DateTime) return $x; 
		else throw DictAccessException::WrongType($key, 'DateTime'); 
    }


	//
	// Structures
	//


	public function stringlist(string $offset) : vec<string> { 
		if(! \array_key_exists($offset, $this->dict)) throw DictAccessException::DNE($offset);
		$x = $this->dict[$offset];

		/* HH_IGNORE_ERROR[4101] Generics */
		if($x is vec) { 
			/* HH_IGNORE_ERROR[4110] Generics */
			return $x; 
		}
		else throw DictAccessException::WrongType($offset, 'vec');

	}
	public function intlist(string $offset) : vec<int> { 
		if(! \array_key_exists($offset, $this->dict)) throw DictAccessException::DNE($offset);
		$x = $this->dict[$offset];

		/* HH_IGNORE_ERROR[4101] Generics */
		if($x is vec) { 
			/* HH_IGNORE_ERROR[4110] Generics */
			return $x; 
		}
		else throw DictAccessException::WrongType($offset, 'vec');
	}
	public function floatlist(string $offset) : vec<float> { 
		if(! \array_key_exists($offset, $this->dict)) throw DictAccessException::DNE($offset);
		$x = $this->dict[$offset];

		/* HH_IGNORE_ERROR[4101] Generics */
		if($x is vec) { 
			/* HH_IGNORE_ERROR[4110] Generics */
			return $x; 
		}
		else throw DictAccessException::WrongType($offset, 'vec');
	}
	public function boollist(string $offset) : vec<bool> { 
		if(! \array_key_exists($offset, $this->dict)) throw DictAccessException::DNE($offset);
		$x = $this->dict[$offset];

		/* HH_IGNORE_ERROR[4101] Generics */
		if($x is vec) { 
			/* HH_IGNORE_ERROR[4110] Generics */
			return $x; 
		}
		else throw DictAccessException::WrongType($offset, 'vec');
	}
	public function DateTimeList(string $offset) : vec<DateTime> { 
		if(! \array_key_exists($offset, $this->dict)) throw DictAccessException::DNE($offset);
		$x = $this->dict[$offset];

		/* HH_IGNORE_ERROR[4101] Generics */
		if($x is vec) { 
			/* HH_IGNORE_ERROR[4110] Generics */
			return $x; 
		}
		else throw DictAccessException::WrongType($offset, 'vec');
	}

	//
	// Dict structures
	//

	public function dict(string $offset) : DictAccess { 
		if(! \array_key_exists($offset, $this->dict)) throw DictAccessException::DNE($offset);
		$x = $this->dict[$offset];

		/* HH_IGNORE_ERROR[4101] Generics */
		/* HH_IGNORE_ERROR[4110] Generics */
		if($x is dict) return new DictAccess($x); 
		else throw DictAccessException::WrongType($offset, 'dict');
	}

	public function dictlist(string $offset) : vec<DictAccess> { 
		if(! \array_key_exists($offset, $this->dict)) throw DictAccessException::DNE($offset);
		$x = $this->dict[$offset];

		/* HH_IGNORE_ERROR[4101] Generics */
		if($x is vec) { 
			/* HH_IGNORE_ERROR[4110] Generics */
			return HH\Lib\Vec\map($x, function(dict<string, nonnull> $newdict) : DictAccess { return new DictAccess($newdict); });
		}
		else throw DictAccessException::WrongType($offset, 'vec');

	}




	//
	// Optionals
	// 

	// Primitives
	public function _int(string $key) : ?int { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->int($key); 
	}
	public function _string(string $key) : ?string { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->string($key); 
	}
	public function _float(string $key) : ?float { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->float($key); 
	}
	public function _bool(string $key) : ?bool { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->bool($key); 
	}
	public function _DateTime(string $key) : ?DateTime { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->int($key); 
	}

	// Lists
	public function _intlist(string $key) : ?vec<int> { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->intlist($key); 
	}
	public function _stringlist(string $key) : ?vec<string> { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->stringlist($key); 
	}
	public function _floatlist(string $key) : ?vec<float> { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->floatlist($key); 
	}
	public function _boollist(string $key) : ?vec<bool> { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->boollist($key); 
	}
	public function _DateTimeList(string $key) : ?vec<DateTime> { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->DateTimeList($key); 
	}

	// Dicts
	public function _dict(string $key) : ?DictAccess { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->dict($key); 
	}
	public function _dictlist(string $key) : ?vec<DictAccess> { 
		if(! \array_key_exists($key, $this->dict)) return NULL; 
		return $this->dictlist($key); 
	}
}
