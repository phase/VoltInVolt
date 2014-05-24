// Copyright © 2013, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.ir.copy;

import watt.conv;

import volt.ir.ir;
import volt.ir.util;
import volt.token.location;

import volt.errors;


Constant copy(Constant cnst)
{
	auto c = new Constant();
	c.location = cnst.location;
	c.type = (cnst.type !is null ? copyType(cnst.type) : null);
	c.u._ulong = cnst.u._ulong;
	c._string = cnst._string;
	c.isNull = cnst.isNull;
	c.arrayData = cnst.arrayData[0 .. cnst.arrayData.length];
	return c;
}

BlockStatement copy(BlockStatement bs)
{
	auto b = new BlockStatement();
	b.location = bs.location;
	b.statements = bs.statements;

	foreach (ref stat; b.statements) {
		stat = copyNode(stat);
	}

	return b;
}

ReturnStatement copy(ReturnStatement rs)
{
	auto r = new ReturnStatement();
	r.location = rs.location;
	r.exp = copyExp(rs.exp);
	return r;
}

BinOp copy(BinOp bo)
{
	auto b = new BinOp();
	b.location = bo.location;
	b.op = bo.op;
	b.left = copyExp(bo.left);
	b.right = copyExp(bo.right);
	return b;
}

IdentifierExp copy(IdentifierExp ie)
{
	auto i = new IdentifierExp();
	i.location = ie.location;
	i.globalLookup = ie.globalLookup;
	i.value = ie.value;
	i.type = copyNode(ie.type);
	return i;
}

TokenExp copy(TokenExp te)
{
	auto newte = new TokenExp(te.type);
	newte.location = te.location;
	return newte;
}


TypeExp copy(TypeExp te)
{
	auto newte = new TypeExp();
	newte.location = te.location;
	newte.type = copyType(te.type);
	return newte;
}

ArrayLiteral copy(ArrayLiteral ar)
{
	auto newar = new ArrayLiteral();
	newar.location = ar.location;
	if (ar.type !is null)
		newar.type = copyType(ar.type);
	newar.values = ar.values[0 .. ar.values.length];
	foreach (ref value; ar.values) {
		value = copyExp(value);
	}
	return newar;
}

ExpReference copy(ExpReference er)
{
	auto newer = new ExpReference();
	newer.location = er.location;
	newer.idents = er.idents[0 .. er.idents.length];
	newer.decl = er.decl;
	newer.rawReference = er.rawReference;
	newer.doNotRewriteAsNestedLookup = er.doNotRewriteAsNestedLookup;
	return newer;
}

Identifier copy(Identifier ident)
{
	auto n = new Identifier();
	n.location = ident.location;
	n.value = ident.value;
	return n;
}

Postfix copy(Postfix pfix)
{
	auto newpfix = new Postfix();
	newpfix.location = pfix.location;
	newpfix.op = pfix.op;
	newpfix.child = copyExp(pfix.child);
	foreach (arg; pfix.arguments) {
		newpfix.arguments ~= copyExp(arg);
	}
	foreach (argTag; pfix.argumentTags) {
		newpfix.argumentTags ~= argTag;
	}
	if (pfix.identifier !is null) {
		newpfix.identifier = copy(pfix.identifier);
	}
	if (newpfix.memberFunction !is null) {
		newpfix.memberFunction = copy(pfix.memberFunction);
	}
	newpfix.isImplicitPropertyCall = pfix.isImplicitPropertyCall;
	return newpfix;
}

/*
 *
 * Type copy
 *
 */


PrimitiveType copy(PrimitiveType old)
{
	auto pt = new PrimitiveType(old.type);
	pt.location = old.location;
	return pt;
}

PointerType copy(PointerType old)
{
	auto pt = new PointerType(copyType(old.base));
	pt.location = old.location;
	return pt;
}

ArrayType copy(ArrayType old)
{
	auto at = new ArrayType(copyType(old.base));
	at.location = old.location;
	return at;
}

StaticArrayType copy(StaticArrayType old)
{
	auto sat = new StaticArrayType();
	sat.location = old.location;
	sat.base = copyType(old.base);
	sat.length = old.length;
	return sat;
}

AAType copy(AAType old)
{
	auto aa = new AAType();
	aa.location = old.location;
	aa.value = copyType(old.value);
	aa.key = copyType(old.key);
	return aa;
}

FunctionType copy(FunctionType old)
{
	auto ft = new FunctionType(old);
	ft.location = old.location;
	ft.ret = copyType(old.ret);
	foreach(ref ptype; ft.params) {
		ptype = copyType(ptype);
	}
	return ft;
}

DelegateType copy(DelegateType old)
{
	auto dg = new DelegateType(old);
	dg.location = old.location;
	dg.ret = copyType(old.ret);
	foreach(ref ptype; dg.params) {
		ptype = copyType(ptype);
	}
	return dg;
}

StorageType copy(StorageType old)
{
	auto st = new StorageType();
	st.location = old.location;
	if (old.base !is null) {
		st.base = copyType(old.base);
	}
	st.type = old.type;
	st.isCanonical = old.isCanonical;
	return st;
}

TypeReference copy(TypeReference old)
{
	auto tr = new TypeReference();
	tr.location = old.location;
	tr.id = copy(old.id);
	if (old.type !is null) {
		assert(false);
	}
	return tr;
}


/*
 *
 * Helpers.
 *
 */


QualifiedName copy(QualifiedName old)
{
	auto q = new QualifiedName();
	q.location = old.location;
	q.identifiers = old.identifiers;
	foreach (ref oldId; q.identifiers) {
		auto id = new Identifier(oldId.value);
		id.location = old.location;
		oldId = id;
	}
	return q;
}

/**
 * Helper function that takes care of up
 * casting the return from copyDeep.
 */
Type copyType(Type t)
{
	switch (t.nodeType) with (NodeType) {
	case PrimitiveType:
		return copy(cast(PrimitiveType)t);
	case PointerType:
		return copy(cast(PointerType)t);
	case ArrayType:
		return copy(cast(ArrayType)t);
	case StaticArrayType:
		return copy(cast(StaticArrayType)t);
	case AAType:
		return copy(cast(AAType)t);
	case FunctionType:
		return copy(cast(FunctionType)t);
	case DelegateType:
		return copy(cast(DelegateType)t);
	case StorageType:
		return copy(cast(StorageType)t);
	case TypeReference:
		return copy(cast(TypeReference)t);
	case Interface:
	case Struct:
	case Class:
	case UserAttribute:
	case Enum:
		throw panic(t.location, "can't copy aggregate types");
	default:
		assert(false);
	}
	assert(false);
}

/**
 * Helper function that takes care of up
 * casting the return from copyDeep.
 */
Exp copyExp(Exp exp)
{
	auto n = copyNode(exp);
	exp = cast(Exp)n;
	assert(exp !is null);
	return exp;
}

Exp copyExp(Location location, Exp exp)
{
	auto e = copyExp(exp);
	e.location = location;
	return e;
}

/**
 * Copies a node and all its children nodes.
 */
Node copyNode(Node n)
{
	final switch (n.nodeType) with (NodeType) {
	case NonVisiting:
		assert(false, "non-visiting node");
	case Constant:
		auto c = cast(Constant)n;
		return copy(c);
	case BlockStatement:
		auto bs = cast(BlockStatement)n;
		return copy(bs);
	case ReturnStatement:
		auto rs = cast(ReturnStatement)n;
		return copy(rs);
	case BinOp:
		auto bo = cast(BinOp)n;
		return copy(bo);
	case IdentifierExp:
		auto ie = cast(IdentifierExp)n;
		return copy(ie);
	case TypeExp:
		auto te = cast(TypeExp)n;
		return copy(te);
	case ArrayLiteral:
		auto ar = cast(ArrayLiteral)n;
		return copy(ar);
	case TokenExp:
		auto te = cast(TokenExp)n;
		return copy(te);
	case ExpReference:
		auto er = cast(ExpReference)n;
		return copy(er);
	case Postfix:
		auto pfix = cast(Postfix)n;
		return copy(pfix);
	case StatementExp:
	case PrimitiveType:
	case TypeReference:
	case PointerType:
	case NullType:
	case ArrayType:
	case StaticArrayType:
	case AAType:
	case AAPair:
	case FunctionType:
	case DelegateType:
	case StorageType:
	case TypeOf:
	case Struct:
	case Class:
	case Interface:
		auto t = cast(Type)n;
		return copyTypeSmart(t.location, t);  /// @todo do correctly.
	case QualifiedName:
	case Identifier:
	case Module:
	case TopLevelBlock:
	case Import:
	case Unittest:
	case Union:
	case Enum:
	case Attribute:
	case StaticAssert:
	case MixinTemplate:
	case MixinFunction:
	case UserAttribute:
	case EmptyTopLevel:
	case Condition:
	case ConditionTopLevel:
	case FunctionDecl:
	case FunctionBody:
	case Variable:
	case Alias:
	case Function:
	case FunctionParam:
	case AsmStatement:
	case IfStatement:
	case WhileStatement:
	case DoStatement:
	case ForStatement:
	case ForeachStatement:
	case LabelStatement:
	case ExpStatement:
	case SwitchStatement:
	case SwitchCase:
	case ContinueStatement:
	case BreakStatement:
	case GotoStatement:
	case WithStatement:
	case SynchronizedStatement:
	case TryStatement:
	case ThrowStatement:
	case ScopeStatement:
	case PragmaStatement:
	case EmptyStatement:
	case ConditionStatement:
	case MixinStatement:
	case AssertStatement:
	case Comma:
	case Ternary:
	case Unary:
	case AssocArray:
	case Assert:
	case StringImport:
	case Typeid:
	case IsExp:
	case TraitsExp:
	case TemplateInstanceExp:
	case FunctionLiteral:
	case StructLiteral:
	case ClassLiteral:
	case EnumDeclaration:
	case FunctionSet:
	case FunctionSetType:
	case VaArgExp:
	case Invalid:
		auto msg = format("invalid node '%s'", toString(n.nodeType));
		throw panic(n.location, msg);
	}
	assert(false);
}
