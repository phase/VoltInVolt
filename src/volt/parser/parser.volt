// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.parser.parser;

import watt.io;
import watt.text.format;

import volt.token.location : Location;
import volt.token.lexer : lex;
import volt.token.token : tokenToString;
import volt.token.source : Source;
import volt.token.stream : TokenType, TokenStream;

import ir = volt.ir.ir;

import volt.parser.base : match;
import volt.parser.toplevel : parseModule;
import volt.parser.statements : parseStatement;
import volt.interfaces : Frontend;


class Parser : Frontend
{
public:
	bool dumpLex;

public:
	override ir.Module parseNewFile(string source, Location loc)
	{
		auto src = new Source(source, loc);
		src.skipScriptLine();
		auto ts = lex(src);
		if (dumpLex)
			doDumpLex(ts);

		// Skip Begin.
		match(ts, TokenType.Begin);

		return .parseModule(ts);
	}

	override ir.Node[] parseStatements(string source, Location loc)
	{
		auto src = new Source(source, loc);
		auto ts = lex(src);
		if (dumpLex)
			doDumpLex(ts);

		match(ts, TokenType.Begin);

		ir.Node[] ret;
		while (/*ts != TokenType.End!!!*/false) {
		//	ret ~= parseStatement(ts);
		}

		return ret;
	}

	override void close()
	{

	}

protected:
	void doDumpLex(TokenStream ts)
	{
		output.writeln("Dumping lexing:");

		// Skip first begin
		ts.get();

		ir.Token t;
		while((t = ts.get()).type != TokenType.End) {
			string l = t.location.toString();
			string tStr = tokenToString[t.type];
			string v = t.value;
			output.writeln(format("%s %s \"%s\"", l, tStr, v));
		}

		output.writeln("");

		ts.reset();
	}
}
