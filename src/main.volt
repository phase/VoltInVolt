module volt.main;

import core.stdc.stdio;

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
		printf("Caught unhandled exception: '%s'\n", e.message);
		return 1;
	}
	assert(false);
}

int realMain(string[] args)
{
	if (args.length == 1) {
		printf("usage: %s [files]\n", args[0]);
		return 1;
	}
	for (size_t i = 1; i < args.length; i++) {
		auto src = new Source(args[i]);
		auto tstream = lex(src);
		Token token;
		printf("---%s---\n", args[i]);
		do { 
			token = tstream.get();
			printf("%s", tokenToString[token.type]);
			printf("(%s)\n", token.location.toString());
		} while (token.type != TokenType.End);
		printf("BEFORE PARSING\n");
		auto mod = parseModule(tstream);
		printf("Parsed a file!\n");
	}
	return 0;
}

