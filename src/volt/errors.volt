// Copyright © 2013, Bernard Helyer.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.errors;

import core.stdc.stdio;

import watt.text.format;

import volt.exceptions;
import volt.token.location;

// Not sure of the best home for this guy.
void warning(Location loc, string message)
{
	printf("%s\n", format("%s: warning: %s", loc.toString(), message));
	return;
}

CompilerException makeUnsupported(Location location, string feature, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("unsupported feature, '%s'", feature), file, line);
}

CompilerException makeError(Location location, string s, string file = __FILE__, size_t line = __LINE__)
{
	// A hack for typer, for now.
	return new CompilerError(location, s, file, line);
}

CompilerException makeExpected(Location location, string s, bool b = false, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("expected %s.", s), b, file, line);
}

CompilerException makeExpected(Location location, const(char)[] expected, const(char)[] got, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("expected '%s', got '%s'.", expected, got), file, line);
}

CompilerException makeUnexpected(Location location, string s, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("unexpected %s.", s), file, line);
}

CompilerException makeNotMember(Location location, string aggregate, string member, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("%s has no member '%s'", aggregate, member), file, line);
}

CompilerException makeFailedLookup(Location location, string lookup, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("unidentified identifier '%s'", lookup), file, line);
}

CompilerException makeNonTopLevelImport(Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "Imports only allowed in top scope", file, line);
}

CompilerException panic(Location location, string msg, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerPanic(location, msg, file, line);
}

CompilerException panic(string msg, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerPanic(msg, file, line);
}

CompilerException panicUnhandled(Location location, string unhandled, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerPanic(location, format("unhandled case '%s'", unhandled), file, line);
}

