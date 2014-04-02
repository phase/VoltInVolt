module volt.main;

import watt.io;

import volt.exceptions;
import volt.token.source;
import volt.token.lexer;
import volt.token.token;
import volt.parser.toplevel;
import ir = volt.ir.ir;

int main(string[] args)
{
	try {
		return realMain(args);
	} catch (Exception e) {
		output.writefln("%s", e.message);
		return 1;
	}
	assert(false);
}

int realMain(string[] args)
{
	if (args.length == 1) {
		output.writefln("usage: %s [files]\n", args[0]);
		return 1;
	}
	foreach (arg; args[1 .. $]) {
		auto src = new Source(arg);
		auto ts = lex(src);
		auto mod = parseModule(ts);
		output.writefln("Parsed file %s.\n", arg);
	}
	return 0;
}
