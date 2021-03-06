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
		return init(args);
	} catch (object.Throwable e) {
		output.writefln("%s", e.message);
		return 1;
	}
	assert(false);
}

int init(string[] args)
{
	if (args.length == 1) {
		output.writefln("usage: %s [files]\n", args[0]);
		return 1;
	}
	foreach (arg; args[1 .. args.length]) {
		auto src = new Source(arg);
		output.writef("Parsing file %s ... ", arg);
		output.flush();
		auto ts = lex(src);
		auto mod = parseModule(ts);
		output.writefln("done");
	}
	return 0;
}
