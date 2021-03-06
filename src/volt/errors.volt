// Copyright © 2013, Bernard Helyer.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.errors;

import watt.io;
import watt.conv;
import watt.text.format;

import ir = volt.ir.ir;

import volt.exceptions;
import volt.token.location;

// Not sure of the best home for this guy.
void warning(Location loc, string message)
{
	output.writeln(format("%s: warning: %s", loc.toString(), message));
}

/*
 *
 *
 * Specific Errors
 *
 *
 */

CompilerException makeBadWithType(Location loc, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError("bad expression type for with statement.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeForeachReverseOverAA(ir.ForeachStatement fes, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(fes.location, "foreach_reverse over associative array.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeAnonymousAggregateRedefines(ir.Aggregate agg, string name, string file = __FILE__, const int line = __LINE__)
{
	auto msg = format("anonymous aggregate redefines '%s'.", name);
	auto e = new CompilerError(agg.location, msg);
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeAnonymousAggregateAtTopLevel(ir.Aggregate agg, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(agg.location, "anonymous struct or union not inside aggregate.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeInvalidMainSignature(ir.Function fn, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(fn.location, "invalid main signature.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeNoValidFunction(Location loc, string fname, ir.Type[] args, string file = __FILE__, const int line = __LINE__)
{
	auto msg = format("no function named '%s' matches arguments %s.", fname, typesString(args));
	auto e = new CompilerError(loc, msg);
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeCVaArgsOnlyOperateOnSimpleTypes(Location loc, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(loc, "C varargs only supports retrieving simple types, due to an LLVM limitation.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeVaFooMustBeLValue(Location loc, string foo, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(loc, format("argument to %s is not an lvalue.", foo));
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeNonLastVariadic(ir.Variable var, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(var.location, "variadic parameter must be last.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeStaticAssert(ir.AssertStatement as, string msg, string file = __FILE__, const int line = __LINE__)
{
	string emsg = format("static assert: %s", msg);
	auto e = new CompilerError(as.location, emsg);
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeConstField(ir.Variable v, string file = __FILE__, const int line = __LINE__)
{
	string emsg = format("const or immutable non local/global field '%s' is forbidden.", v.name);
	auto e = new CompilerError(v.location, emsg);
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeAssignToNonStaticField(ir.Variable v, string file = __FILE__, const int line = __LINE__)
{
	string emsg = format("attempted to assign to non local/global field %s.", v.name);
	auto e = new CompilerError(v.location, emsg);
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeSwitchBadType(ir.Node node, ir.Type type, string file = __FILE__, const int line = __LINE__)
{
	string emsg = format("bad switch type '%s'.", errorString(type));
	auto e = new CompilerError(node.location, emsg);
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeSwitchDuplicateCase(ir.Node node, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(node.location, "duplicate case in switch statement.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeFinalSwitchBadCoverage(ir.Node node, string file = __FILE__, const int line = __LINE__)
{
	auto e = new CompilerError(node.location, "final switch statement doesn't cover all enum members.");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeArchNotSupported(string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError("arch not supported on current platform.", file, line);
}

CompilerException makeNotTaggedOut(ir.Exp exp, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(exp.location, "out parameter not tagged as out.", file, line);
}

CompilerException makeNotTaggedRef(ir.Exp exp, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(exp.location, "ref parameter not tagged as ref.", file, line);
}

CompilerException makeFunctionNameOutsideOfFunction(ir.TokenExp fexp, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(fexp.location, format("%s occurring outside of function.", fexp.type == ir.TokenExp.Type.PrettyFunction ? "__PRETTY_FUNCTION__" : "__FUNCTION__"), file, line);
}

CompilerException makeMultipleValidModules(ir.Node node, string[] paths, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("multiple modules are valid: %s.", paths), file, line);
}

CompilerException makeAlreadyLoaded(ir.Module m, string filename, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(m.location, format("module %s already loaded '%s'.", m.name.toString(), filename), file, line);
}

CompilerException makeCannotOverloadNested(ir.Node node, ir.Function fn, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("cannot overload nested function '%s'.", fn.name), file, line);
}

CompilerException makeUsedBeforeDeclared(ir.Node node, ir.Variable var, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("variable '%s' used before declaration.", var.name), file, line);
}


CompilerException makeStructConstructorsUnsupported(ir.Node node, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, "struct constructors are currently unsupported.", file, line);
}

CompilerException makeCallingStaticThroughInstance(ir.Node node, ir.Function fn, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("calling local or global function '%s' through instance variable.", fn.name), file, line);
}

CompilerException makeMarkedOverrideDoesNotOverride(ir.Node node, ir.Function fn, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("function '%s' is marked as override but does not override any functions.", fn.name), file, line);
}

CompilerException makeAbstractHasToBeMember(ir.Node node, ir.Function fn, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("function '%s' is marked as abstract but is not a member of an abstract class.", fn.name), file, line);
}

CompilerException makeAbstractBodyNotEmpty(ir.Node node, ir.Function fn, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("function '%s' is marked as abstract but it has an implementation.", fn.name), file, line);
}

CompilerException makeNewAbstract(ir.Node node, ir.Class _class, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("cannot create instance of abstract class '%s'.", _class.name), file, line);
}

CompilerException makeBadAbstract(ir.Node node, ir.Attribute attr, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, "only classes and functions may be marked as abstract.", file, line);
}

CompilerException makeCannotImport(ir.Node node, ir.Import _import, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("can't find module '%s'.", _import.name), file, line);
}

CompilerException makeNotAvailableInCTFE(ir.Node node, ir.Node feature, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("%s is currently unevaluatable at compile time.", toString(feature.nodeType)), file, line);
}

CompilerException makeShadowsDeclaration(ir.Node a, ir.Node b, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(a.location, format("shadows declaration at %s.", b.location), file, line);
}

CompilerException makeMultipleDefaults(Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "multiple default cases defined.", file, line);
}

CompilerException makeFinalSwitchWithDefault(Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "final switch with default case.", file, line);
}

CompilerException makeNoDefaultCase(Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "no default case.", file, line);
}

CompilerException makeTryWithoutCatch(Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "try statement must have a catch block and/or a finally block.", file, line);
}

CompilerException makeMultipleOutBlocks(Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "multiple in blocks specified for single function.", file, line);
}

CompilerException makeNeedOverride(ir.Function overrider, ir.Function overridee, string file = __FILE__, size_t line = __LINE__)
{
	string emsg = format("function '%s' overrides function at %s but is not marked with 'override'.", overrider.name, overridee.location);
	return new CompilerError(overrider.location, emsg, file, line);
}

CompilerException makeThrowOnlyThrowable(ir.Exp exp, ir.Type type, string file = __FILE__, size_t line = __LINE__)
{
	string emsg = format("can not throw expression of type '%s'", errorString(type));
	return new CompilerError(exp.location, emsg, file, line);
}

CompilerException makeThrowNoInherits(ir.Exp exp, ir.Class clazz, string file = __FILE__, size_t line = __LINE__)
{
	string emsg = format("can not throw class of type '%s' as it does not inherit from object.Throwable", errorString(clazz));
	return new CompilerError(exp.location, emsg, file, line);
}

CompilerException makeInvalidAAKey(ir.AAType aa, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(aa.location, format("'%s' is an invalid AA key", errorString(aa.key)), file, line);
}

CompilerException makeBadAAAssign(Location location, string file = __FILE__, size_t line = __LINE__)
{
    return new CompilerError(location, "assigning AA's to each other is not allowed due to semantic inconsistencies.", file, line);
}

CompilerException makeBadAANullAssign(Location location, string file = __FILE__, size_t line = __LINE__)
{
    return new CompilerError(location, "cannot set AA to null, use [] instead.", file, line);
}


/*
 *
 *
 * General Util
 *
 *
 */

CompilerException makeUnsupported(Location location, string feature, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("unsupported feature, '%s'", feature), file, line);
}

CompilerException makeError(Location location, string s, string file = __FILE__, size_t line = __LINE__)
{
	// A hack for typer, for now.
	return new CompilerError(location, s, file, line);
}

CompilerException makeExpected(ir.Node node, string s, string file = __FILE__, size_t line = __LINE__)
{
	return makeExpected(node.location, s, false, file, line);
}

CompilerException makeExpected(Location location, string s, bool b, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("expected %s.", s), b, file, line);
}

CompilerException makeExpected(Location location, string expected, string got, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("expected '%s', got '%s'.", expected, got), file, line);
}

CompilerException makeUnexpected(ir.Location location, string s, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("unexpected %s.", s), file, line);
}

CompilerException makeBadOperation(ir.Node node, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, "bad operation.", file, line);
}

CompilerException makeExpectedContext(ir.Node node, ir.Node node2, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, "expected context pointer.", file, line);
}


/*
 *
 *
 * Type Conversions
 *
 *
 */

CompilerException makeBadImplicitCast(ir.Node node, ir.Type from, ir.Type to, string file = __FILE__, size_t line = __LINE__)
{
	string emsg = format("cannot implicitly convert '%s' to '%s'.", errorString(from), errorString(to));
	return new CompilerError(node.location, emsg, file, line);
}

CompilerException makeCannotModify(ir.Node node, ir.Type type, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("cannot modify '%s'.", errorString(type)), file, line);
}

CompilerException makeNotLValue(ir.Node node, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, "expected lvalue.", file, line);
}

CompilerException makeTypeIsNot(ir.Node node, ir.Type from, ir.Type to, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("type '%s' is not '%s' as expected.", errorString(from), errorString(to)), file, line);
}

CompilerException makeInvalidType(ir.Node node, ir.Type type, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("bad type '%s'", errorString(type)), file, line);
}

CompilerException makeInvalidUseOfStore(ir.Node node, ir.Store store, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("invalid use of store '%s'.", store.name), file, line);
}

/*
 *
 *
 * Look ups
 *
 *
 */

CompilerException makeWithCreatesAmbiguity(Location loc, string file = __FILE__, size_t line = __LINE__)
{
	auto e = new CompilerError(loc, "ambiguous lookup due to with block(s).");
	e.file = file;
	e.line = line;
	return e;
}

CompilerException makeInvalidThis(ir.Node node, ir.Type was, ir.Type expected, string member, string file = __FILE__, size_t line = __LINE__)
{
	string emsg = format("'this' is of type '%s' expected '%s' to access member '%s'", errorString(was), errorString(expected), member);
	return new CompilerError(node.location, emsg, file, line);
}

CompilerException makeNotMember(ir.Node node, ir.Type aggregate, string member, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("'%s' has no member '%s'", errorString(aggregate), member), file, line);
}

CompilerException makeNotMember(Location location, string aggregate, string member, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("%s has no member '%s'", aggregate, member), file, line);
}

CompilerException makeFailedLookup(ir.Node node, string lookup, string file = __FILE__, size_t line = __LINE__)
{
	return makeFailedLookup(node.location, lookup, file, line);
}

CompilerException makeFailedLookup(Location location, string lookup, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("unidentified identifier '%s'", lookup), file, line);
}

CompilerException makeNonTopLevelImport(Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "Imports only allowed in top scope", file, line);
}

/*
 *
 *
 * Functions
 *
 *
 */

CompilerException makeWrongNumberOfArguments(ir.Node node, size_t got, size_t expected, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("wrong number of arguments; got %s, expected %s.", got, expected), file, line);
}

CompilerException makeBadCall(ir.Node node, ir.Type type, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, format("cannot call '%s'.", errorString(type)), file, line);
}

CompilerException makeCannotDisambiguate(ir.Node node, ir.Function[] functions, string file = __FILE__, size_t line = __LINE__)
{
	return makeCannotDisambiguate(node.location, functions, file, line);
}

CompilerException makeCannotDisambiguate(Location location, ir.Function[] functions, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, format("cannot disambiguate between %s functions.", functions.length), file, line);
}

CompilerException makeCannotInfer(ir.Location location, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(location, "not enough information to infer type.", true, file, line);
}

CompilerException makeCannotLoadDynamic(ir.Node node, ir.Function fn, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerError(node.location, "can not @loadDynamic function with body", file, line);
}


/*
 *
 *
 * Panics
 *
 *
 */

CompilerException panicOhGod(ir.Node node, string file = __FILE__, size_t line = __LINE__)
{
	return panic(node.location, "Oh god.", file, line);
}

CompilerException panic(ir.Node node, string msg, string file = __FILE__, size_t line = __LINE__)
{
	return panic(node.location, msg, file, line);
}

CompilerException panic(Location location, string msg, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerPanic(location, msg, file, line);
}

CompilerException panic(string msg, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerPanic(msg, file, line);
}

CompilerException panicUnhandled(ir.Node node, string unhandled, string file = __FILE__, size_t line = __LINE__)
{
	return panicUnhandled(node.location, unhandled, file, line);
}

CompilerException panicUnhandled(Location location, string unhandled, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerPanic(location, format("unhandled case '%s'", unhandled), file, line);
}

CompilerException panicNotMember(ir.Node node, string aggregate, string field, string file = __FILE__, size_t line = __LINE__)
{
	auto str = format("0x%s no field name '%s' in struct '%s'",
	                  toString(*cast(size_t*)&node),
	                  field, aggregate);
	return new CompilerPanic(node.location, str, file, line);
}

CompilerException panicExpected(ir.Location location, string msg, string file = __FILE__, size_t line = __LINE__)
{
	return new CompilerPanic(location, format("expected %s", msg), file, line);
}

void panicAssert(ir.Node node, bool condition, string file = __FILE__, size_t line = __LINE__)
{
	if (!condition) {
		throw panic(node.location, "assertion failure", file, line);
	}
}

private:

string typesString(ir.Type[] types)
{
	char[] buf = cast(char[]) "("[0 .. 1];
	foreach (i, type; types) {
		buf ~= cast(char[]) errorString(type);
		if (i < types.length - 1) {
			buf ~= cast(char[]) ", "[0 .. 2];
		}
	}
	buf ~= cast(char[]) ")"[0 .. 1];
	return cast(string) buf[0 .. buf.length];
}

@property string errorString(ir.Type type)
{

	switch(type.nodeType) with(ir.NodeType) {
	case PrimitiveType:
		ir.PrimitiveType prim = cast(ir.PrimitiveType)type;
		return toLower(format("%s", prim.type));
	case TypeReference:
		ir.TypeReference tr = cast(ir.TypeReference)type;
		return errorString(tr.type);
	case PointerType:
		ir.PointerType pt = cast(ir.PointerType)type;
		return format("%s*", errorString(pt.base));
	case NullType:
		return "null";
	case ArrayType:
		ir.ArrayType at = cast(ir.ArrayType)type;
		return format("%s[]", errorString(at.base));
	case StaticArrayType:
		ir.StaticArrayType sat = cast(ir.StaticArrayType)type;
		return format("%s[%d]", errorString(sat.base), sat.length);
	case AAType:
		ir.AAType aat = cast(ir.AAType)type;
		return format("%s[%s]", errorString(aat.value), errorString(aat.key));
	case FunctionType:
	case DelegateType:
		ir.CallableType c = cast(ir.CallableType)type;

		string ctype = type.nodeType == ir.NodeType.FunctionType ? "function" : "delegate";

		char[] params;
		foreach (i, param; c.params) {
			params ~= cast(char[]) errorString(param);
			if (i < c.params.length - 1) {
				params ~= cast(char[]) ", ";
			}
		}

		return format("%s %s(%s)", errorString(c.ret), ctype, params);
	case StorageType:
		ir.StorageType st = cast(ir.StorageType)type;
		return format("%s(%s)", toLower(format("%s", st.type)), errorString(st.base));
	case Class:
	case Struct:
		auto agg = cast(ir.Aggregate)type;
		assert(agg !is null);
		return agg.name;
	default:
		return type.toString();
	}

	assert(0);
}
