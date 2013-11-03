module volt.main;

import core.stdc.stdio;

import volt.token.source;
import volt.token.lexer;
import volt.token.token;

int main(string[] args)
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
		printf("\n");
	}
	return 0;
}

