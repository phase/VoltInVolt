module volt.main;

import core.stdc.stdio;

import volt.token.source;
import volt.token.lexer;
import volt.token.token;
import volt.parser.toplevel;
import ir = volt.ir.ir;

int main(string[] args)
{
	if (args.length == 1) {
		printf("usage: %s [files]\n", args[0]);
		return 1;
	}
	foreach (arg; args) {
		auto src = new Source(arg);
		auto ts = lex(src);
		auto mod = parseModule(ts);
		printf("Parsed file %s.\n", arg);
	}
	return 0;
}

