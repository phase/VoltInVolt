module volt.util.string;

import volt.errors;
import volt.token.location;

import watt.conv;
import watt.text.utf;

//alias unescape!char unescapeString;
//alias unescape!wchar unescapeWstring;
//alias unescape!dchar unescapeDstring;

bool isHex(dchar d)
{
	switch (d) {
	case 'a', 'b', 'c', 'd', 'e', 'f',
		 'A', 'B', 'C', 'D', 'E', 'F',
		 '0', '1', '2', '3', '4', '5',
		 '6', '7', '8', '9':
		return true;
	default:
		return false;
	}
}

// Manual template expansion! (^_^;)
void[] unescapeString(Location location, const char[] s)
{
	char[] output;

	bool escaping, hexing, unicoding;
	char[] hexchars;
	foreach (c; s) {
		// \uXXXX
		if (unicoding) {
			if (!isHex(c)) {
				if (hexchars.length == 4) {
					ushort i;
					//try {
						i = cast(ushort) toInt(hexchars, 16);
					//} catch (ConvException) {
					//	throw makeExpected(location, "unicode codepoint specification");
					//}
					encode(ref output, i);
					unicoding = false;
					continue;
				} else if (hexchars.length == 8) {
					uint i;
					//try {
						i = cast(uint) toInt(hexchars, 16);
					//} catch (ConvException) {
					//	throw makeExpected(location, "unicode codepoint specification");
					//}
					encode(ref output, i);
					unicoding = false;
					continue;
				} else { 
					throw makeExpected(location, "unicode codepoint specification", false);
				}
			}
			if (hexchars.length == 8) {
				uint i;
				//try {
					i = cast(uint) toInt(hexchars, 16);
				//} catch (ConvException) {
				//	throw makeExpected(location, "unicode codepoint specification");
				//}
				encode(ref output, i);
				unicoding = false;
				continue;
			}
			hexchars ~= c;
			continue;
		}

		// \xXX
		if (hexing) {
			if (!isHex(c)) {
				throw makeExpected(location, "hex digit", false);
			}
			hexchars ~= c;
			if (hexchars.length == 2) {
				//try {
					output ~= cast(char) toInt(hexchars, 16);
				//} catch (ConvException) {
				//	throw makeExpected(location, "hex digit");
				//}
				hexing = false;
				hexchars.length = 0;
			}
			continue;
		}

		// \X
		if (escaping) {
			switch (c) {
				case '\'': encode(ref output, '\''); break;
				case '\"': encode(ref output, '\"'); break;
				case '\?': encode(ref output, '\?'); break;
				case '\\': encode(ref output, '\\'); break;
				case 'a': encode(ref output, '\a'); break;
				case 'b': encode(ref output, '\b'); break;
				case 'f': encode(ref output, '\f'); break;
				case 'n': encode(ref output, '\n'); break;
				case 'r': encode(ref output, '\r'); break;
				case 't': encode(ref output, '\t'); break;
				case 'v': encode(ref output, '\v'); break;
				case '0': encode(ref output, '\0'); break;
				case 'x':
					escaping = false;
					hexing = true;
					hexchars.length = 0;
					continue;
				case 'u', 'U':
					unicoding = true;
					hexchars.length = 0;
					continue;
				// @todo Named character entities. http://www.w3.org/TR/html5/named-character-references.html
				default:
					throw makeExpected(location, "valid escape", false);
			}
			escaping = false;
			continue;
		}

		if (c == '\\') {
			escaping = true;
			continue;
		} else {
			output ~= c;
		}
	}

	if (escaping) {
		throw makeExpected(location, "valid escape.", false);
	}

	return cast(void[]) output;
}

/+ void[] unescape(T)(Location location, const T[] s)
{
	T[] output;

	bool escaping, hexing, unicoding;
	dchar[] hexchars;
	foreach (c; s) {
		// \uXXXX
		if (unicoding) {
			if (!isHex(c)) {
				if (hexchars.length == 4) {
					ushort i;
					try {
						i = parse!ushort(hexchars, 16);
					} catch (ConvException) {
						throw makeExpected(location, "unicode codepoint specification");
					}
					encode(output, i);
					unicoding = false;
					continue;
				} else if (hexchars.length == 8) {
					uint i;
					try {
						i = parse!uint(hexchars, 16);
					} catch (ConvException) {
						throw makeExpected(location, "unicode codepoint specification");
					}
					encode(output, i);
					unicoding = false;
					continue;
				} else { 
					throw makeExpected(location, "unicode codepoint specification");
				}
			}
			if (hexchars.length == 8) {
				uint i;
				try {
					i = parse!uint(hexchars, 16);
				} catch (ConvException) {
					throw makeExpected(location, "unicode codepoint specification");
				}
				encode(output, i);
				unicoding = false;
				continue;
			}
			hexchars ~= c;
			continue;
		}

		// \xXX
		if (hexing) {
			if (!isHex(c)) {
				throw makeExpected(location, "hex digit");
			}
			hexchars ~= c;
			if (hexchars.length == 2) {
				try {
					output ~= parse!ubyte(hexchars, 16);
				} catch (ConvException) {
					throw makeExpected(location, "hex digit");
				}
				hexing = false;
				hexchars.length = 0;
			}
			continue;
		}

		// \X
		if (escaping) {
			switch (c) {
				case '\'': encode(output, '\''); break;
				case '\"': encode(output, '\"'); break;
				case '\?': encode(output, '\?'); break;
				case '\\': encode(output, '\\'); break;
				case 'a': encode(output, '\a'); break;
				case 'b': encode(output, '\b'); break;
				case 'f': encode(output, '\f'); break;
				case 'n': encode(output, '\n'); break;
				case 'r': encode(output, '\r'); break;
				case 't': encode(output, '\t'); break;
				case 'v': encode(output, '\v'); break;
				case '0': encode(output, 0); break;
				case 'x':
					escaping = false;
					hexing = true;
					hexchars.length = 0;
					continue;
				case 'u', 'U':
					unicoding = true;
					hexchars.length = 0;
					continue;
				// @todo Named character entities. http://www.w3.org/TR/html5/named-character-references.html
				default:
					throw makeExpected(location, "valid escape");
			}
			escaping = false;
			continue;
		}

		if (c == '\\') {
			escaping = true;
			continue;
		} else {
			output ~= c;
		}
	}

	if (escaping) {
		throw makeExpected(location, "valid escape.");
	}

	return output;
}+/

/**
 * Generate a hash.
 * djb2 algorithm stolen from http://www.cse.yorku.ca/~oz/hash.html
 *
 * This needs to correspond with the implementation
 * in vrt.string in the runtime. 
 */
uint hash(void* ptr, size_t length)
{
	uint h = 5381;

	ubyte* uptr = cast(ubyte*) ptr;

	for (size_t i = 0; i < length; i++) {
		h = ((h << 5) + h) + uptr[i];
	}

	return h;
}

