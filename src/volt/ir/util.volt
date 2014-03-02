// Copyright © 2013, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.ir.util;

import volt.errors;
import volt.interfaces : LanguagePass;
import volt.token.location;
//import volt.semantic.util : canonicaliseStorageType;
import volt.util.string : unescapeString;
import volt.ir.ir;
import volt.ir.copy;


/**
 * Builds a QualifiedName from a string.
 */
QualifiedName buildQualifiedName(Location loc, string value)
{
	auto i = new Identifier(value);
	i.location = loc;
	auto q = new QualifiedName();
	q.identifiers = new Identifier[](1);
	q.identifiers[0] = i;
	q.location = loc;
	return q;
}

/**
 * Builds a QualifiedName from an array.
 */
QualifiedName buildQualifiedName(Location loc, string[] value)
{
	auto idents = new Identifier[](value.length);
	for (size_t i = 0; i < value.length; i++) {
		idents[i] = new Identifier(value[i]);
		idents[i].location = loc;
	}

	auto q = new QualifiedName();
	q.identifiers = idents;
	q.location = loc;
	return q;
}

/**
 * Builds a QualifiedName from a Identifier.
 */
QualifiedName buildQualifiedNameSmart(Identifier i)
{
	auto q = new QualifiedName();
	q.identifiers = new Identifier[](1);
	q.identifiers[0] = new Identifier(i);
	q.location = i.location;
	return q;
}

/**
 * Return the scope from the given type if it is,
 * a aggregate or a derivative from one.
 */
Scope getScopeFromType(Type type)
{
	switch (type.nodeType) with (NodeType) {
	case TypeReference:
		auto asTypeRef = cast(TypeReference) type;
		assert(asTypeRef !is null);
		assert(asTypeRef.type !is null);
		return getScopeFromType(asTypeRef.type);
	case ArrayType:
		auto asArray = cast(ArrayType) type;
		assert(asArray !is null);
		return getScopeFromType(asArray.base);
	case PointerType:
		auto asPointer = cast(PointerType) type;
		assert(asPointer !is null);
		return getScopeFromType(asPointer.base);
	case Struct:
		auto asStruct = cast(Struct) type;
		assert(asStruct !is null);
		return asStruct.myScope;
	case Union:
		auto asUnion = cast(Union) type;
		assert(asUnion !is null);
		return asUnion.myScope;
	case Class:
		auto asClass = cast(Class) type;
		assert(asClass !is null);
		return asClass.myScope;
	case Interface:
		auto asInterface = cast(_Interface) type;
		assert(asInterface !is null);
		return asInterface.myScope;
	case UserAttribute:
		auto asAttr = cast(UserAttribute) type;
		assert(asAttr !is null);
		return asAttr.myScope;
	case Enum:
		auto asEnum = cast(Enum) type;
		assert(asEnum !is null);
		return asEnum.myScope;
	default:
		return null;
	}
	assert(false);
}

/**
 * For the given store get the scope that it introduces.
 *
 * Returns null for Values and non-scope types.
 */
Scope getScopeFromStore(Store store)
{
	final switch(store.kind) with (Store.Kind) {
	case Scope:
		return store.s;
	case Type:
		auto type = cast(Type)store.node;
		assert(type !is null);
		return getScopeFromType(type);
	case Value:
	case Function:
	case FunctionParam:
	case Template:
	case EnumDeclaration:
	case Expression:
		return null;
	case Alias:
		throw panic(store.node.location, "unresolved alias");
	}
	assert(false);
}

/**
 * Does a smart copy of a type.
 *
 * Meaning that well copy all types, but skipping
 * TypeReferences, but inserting one when it comes
 * across a named type.
 */
Type copyTypeSmart(Location loc, Type type)
{
	switch (type.nodeType) with (NodeType) {
	case PrimitiveType:
		auto pt = cast(PrimitiveType)type;
		pt.location = loc;
		pt = new PrimitiveType(pt.type);
		return pt;
	case PointerType:
		auto pt = cast(PointerType)type;
		pt.location = loc;
		pt = new PointerType(copyTypeSmart(loc, pt.base));
		return pt;
	case ArrayType:
		auto at = cast(ArrayType)type;
		at.location = loc;
		at = new ArrayType(copyTypeSmart(loc, at.base));
		return at;
	case StaticArrayType:
		auto asSat = cast(StaticArrayType)type;
		auto sat = new StaticArrayType();
		sat.location = loc;
		sat.base = copyTypeSmart(loc, asSat.base);
		sat.length = asSat.length;
		return sat;
	case AAType:
		auto asAA = cast(AAType)type;
		auto aa = new AAType();
		aa.location = loc;
		aa.value = copyTypeSmart(loc, asAA.value);
		aa.key = copyTypeSmart(loc, asAA.key);
		return aa;
	case FunctionType:
		auto asFt = cast(FunctionType)type;
		auto ft = new FunctionType(asFt);
		ft.location = loc;
		ft.ret = copyTypeSmart(loc, ft.ret);
		foreach(i, ref t; ft.params) {
			t = copyTypeSmart(loc, t);
		}
		return ft;
	case DelegateType:
		auto asDg = cast(DelegateType)type;
		auto dg = new DelegateType(asDg);
		dg.location = loc;
		dg.ret = copyTypeSmart(loc, dg.ret);
		foreach(i, ref t; dg.params) {
			t = copyTypeSmart(loc, t);
		}
		return dg;
	case StorageType:
		auto asSt = cast(StorageType)type;
		auto st = new StorageType();
		st.location = loc;
		if (asSt.base !is null) st.base = copyTypeSmart(loc, asSt.base);
		st.type = asSt.type;
		st.isCanonical = asSt.isCanonical;
		return st;
	case TypeReference:
		auto tr = cast(TypeReference)type;
		assert(tr.type !is null);
		return copyTypeSmart(loc, tr.type);
	case NullType:
		auto nt = new NullType();
		nt.location = type.location;
		return nt;
	case UserAttribute:
	case Interface:
	case Struct:
	case Class:
	case Union:
	case Enum:
		auto s = getScopeFromType(type);
		/// @todo Get fully qualified name for type.
		return buildTypeReference(loc, type, s !is null ? s.name : null);
	default:
		throw panicUnhandled(type.location, cast(string) toString(type.nodeType));
	}
	assert(false);
}

TypeReference buildTypeReference(Location loc, Type type, string[] names...)
{
	auto tr = new TypeReference();
	tr.location = loc;
	tr.type = type;
	tr.id = buildQualifiedName(loc, names);
	return tr;
}

StorageType buildStorageType(Location loc, StorageType.Kind kind, Type base)
{
	auto storage = new StorageType();
	storage.location = loc;
	storage.type = kind;
	storage.base = base;
	return storage;
}

/**
 * Build a PrimitiveType.
 */
PrimitiveType buildPrimitiveType(Location loc, PrimitiveType.Kind kind)
{
	auto pt = new PrimitiveType(kind);
	pt.location = loc;
	return pt;
}

ArrayType buildArrayType(Location loc, Type base)
{
	auto array = new ArrayType();
	array.location = loc;
	array.base = base;
	return array;
}

ArrayType buildArrayTypeSmart(Location loc, Type base)
{
	auto array = new ArrayType();
	array.location = loc;
	array.base = copyTypeSmart(loc, base);
	return array;
}

PrimitiveType buildVoid(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Void); }
PrimitiveType buildBool(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Bool); }
PrimitiveType buildChar(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Char); }
PrimitiveType buildDchar(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Dchar); }
PrimitiveType buildWchar(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Wchar); }
PrimitiveType buildByte(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Byte); }
PrimitiveType buildUbyte(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Ubyte); }
PrimitiveType buildShort(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Short); }
PrimitiveType buildUshort(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Ushort); }
PrimitiveType buildInt(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Int); }
PrimitiveType buildUint(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Uint); }
PrimitiveType buildLong(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Long); }
PrimitiveType buildUlong(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Ulong); }
PrimitiveType buildSizeT(Location loc, LanguagePass lp) { return lp.settings.getSizeT(loc); }
PrimitiveType buildFloat(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Float); }
PrimitiveType buildDouble(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Double); }
PrimitiveType buildReal(Location loc) { return buildPrimitiveType(loc, PrimitiveType.Kind.Real); }

/**
 * Build a string (immutable(char)[]) type.
 */
ArrayType buildString(Location loc)
{
	auto stor = buildStorageType(loc, StorageType.Kind.Immutable, buildChar(loc));
	return buildArrayType(loc, stor);
}

ArrayType buildStringArray(Location loc)
{
	return buildArrayType(loc, buildString(loc));
}


/**
 * Build a void* type.
 */
PointerType buildVoidPtr(Location loc)
{
	auto pt = new PointerType(buildVoid(loc));
	pt.location = loc;

	return pt;
}

PointerType buildPtrSmart(Location loc, Type base)
{
	auto pt = new PointerType(copyTypeSmart(loc, base));
	pt.location = loc;

	return pt;
}

ArrayLiteral buildArrayLiteralSmart(Location loc, Type type, Exp[] exps...)
{
	auto literal = new ArrayLiteral();
	literal.location = loc;
	literal.type = copyTypeSmart(loc, type);
	literal.values = exps[0 .. exps.length];
	return literal;
}

StructLiteral buildStructLiteralSmart(Location loc, Type type, Exp[] exps)
{
	auto literal = new StructLiteral();
	literal.location = loc;
	literal.type = copyTypeSmart(loc, type);
	literal.exps = exps[0 .. exps.length];
	return literal;
}

/**
 * Add a Variable to the BlockStatement scope and either to
 * its statement or if StatementExp given to it instead.
 */
void addVariable(BlockStatement b, StatementExp statExp, Variable var)
{
	b.myScope.addValue(var, var.name);
	if (statExp !is null) {
		statExp.statements ~= var;
	} else {
		b.statements ~= var;
	}
	return;
}

/**
 * Build a Variable, while not being smart about its type.
 */
Variable buildVariable(Location loc, Type type, Variable.Storage st, string name, Exp assign = null)
{
	auto var = new Variable();
	var.location = loc;
	var.name = name;
	var.type = type;
	var.storage = st;
	var.assign = assign;

	return var;
}

/**
 * Build a Variable with an anon. name and insert it into the BlockStatement
 * or StatementExp if given. Note even if you want the Variable to end up in
 * the StatementExp you must give it the BlockStatement that the StatementExp
 * lives in as the variable will be added to its scope and generated a uniqe
 * name from its context.
 */
Variable buildVariableAnonSmart(Location loc, BlockStatement b,
                                   StatementExp statExp,
                                   Type type, Exp assign)
{
	auto name = b.myScope.genAnonIdent();
	auto var = buildVariable(loc, type, Variable.Storage.Function, name, assign);
	addVariable(b, statExp, var);
	return var;
}

/**
 * Copy a Variable, while being smart about its type, does
 * not copy the the assign exp on the Variable.
 */
Variable copyVariableSmart(Location loc, Variable right)
{
	return buildVariable(loc, copyTypeSmart(loc, right.type), right.storage, right.name);
}

Variable[] copyVariablesSmart(Location loc, Variable[] vars)
{
	auto outVars = new Variable[](vars.length);
	foreach (i, var; vars) {
		outVars[i] = copyVariableSmart(loc, var);
	}
	return outVars;
}

/**
 * Get ExpReferences from a list of variables.
 */
Exp[] getExpRefs(Location loc, FunctionParam[] vars)
{
	auto erefs = new Exp[](vars.length);
	foreach (i, var; vars) {
		erefs[i] = buildExpReference(loc, var, var.name);
	}
	return erefs;
}

/**
 * Build a Variable, while being smart about its type.
 */
Variable buildVariableSmart(Location loc, Type type, Variable.Storage st, string name)
{
	return buildVariable(loc, copyTypeSmart(loc, type), st, name);
}

/**
 * Builds a usable ExpReference.
 */
ExpReference buildExpReference(Location loc, Declaration decl, string[] names...)
{
	auto varRef = new ExpReference();
	varRef.location = loc;
	varRef.decl = decl;
	varRef.idents ~= names;

	return varRef;
}

/**
 * Builds a constant int.
 */
Constant buildConstantInt(Location loc, int value)
{
	auto c = new Constant();
	c.location = loc;
	c._int = value;
	c.type = buildInt(loc);

	return c;
}

Constant buildConstantUint(Location loc, uint value)
{
	auto c = new Constant();
	c.location = loc;
	c._uint = value;
	c.type = buildUint(loc);

	return c;
}

Constant buildConstantLong(Location loc, long value)
{
	auto c = new Constant();
	c.location = loc;
	c._long = value;
	c.type = buildLong(loc);

	return c;
}

Constant buildConstantUlong(Location loc, ulong value)
{
	auto c = new Constant();
	c.location = loc;
	c._ulong = value;
	c.type = buildUlong(loc);

	return c;
}

/**
 * Builds a constant bool.
 */
Constant buildConstantBool(Location loc, bool val)
{
	auto c = new Constant();
	c.location = loc;
	c._bool = val;
	c.type = buildBool(loc);

	return c;
}

Constant buildConstantNull(Location loc, Type base)
{
	auto c = new Constant();
	c.location = loc;
	c._pointer = null;
	c.type = copyTypeSmart(loc, base);
	c.type.location = loc;
	c.isNull = true;
	return c;
}

/**
 * Gets a size_t Constant and fills it with a value.
 */
Constant buildSizeTConstant(Location loc, LanguagePass lp, int val)
{
	auto c = new Constant();
	c.location = loc;
	auto prim = lp.settings.getSizeT(loc);
	// Uh, I assume just c._uint = val would work, but I can't test it here, so just be safe.
	if (prim.type == PrimitiveType.Kind.Ulong) {
		c._ulong = val;
	} else {
		c._uint = cast(uint) val;
	}
	c.type = prim;
	return c;
}

/**
 * Builds a constant string.
 */
version (none) Constant buildStringConstant(Location loc, string val)
{
	auto c = new Constant();
	c.location = loc;
	c._string = val;
	auto stor = buildStorageType(loc, StorageType.Kind.Immutable, buildChar(loc));
	canonicaliseStorageType(stor);
	c.type = buildArrayType(loc, stor);
	assert((c._string[$-1] == '"' || c._string[$-1] == '`') && c._string.length >= 2);
	c.arrayData = unescapeString(loc, c._string[1 .. $-1]);
	return c;
}

/**
 * Build a constant to insert to the IR from a resolved EnumDeclaration.
 */
Constant buildConstant(Location loc, EnumDeclaration ed)
{
	auto cnst = cast(Constant) ed.assign;
	auto c = new Constant();
	c.location = loc;
	c._ulong = cnst._ulong;
	c._string = cnst._string;
	c.arrayData = cnst.arrayData;
	c.type = copyTypeSmart(loc, ed.type);

	return c;
}

Constant buildTrue(Location loc) { return buildConstantBool(loc, true); }
Constant buildFalse(Location loc) { return buildConstantBool(loc, false); }

/**
 * Build a cast and sets the location, does not call copyTypeSmart.
 */
Unary buildCast(Location loc, Type type, Exp exp)
{
	auto cst = new Unary(type, exp);
	cst.location = loc;
	return cst;
}

/**
 * Build a cast, sets the location and calling copyTypeSmart
 * on the type, to avoid duplicate nodes.
 */
Unary buildCastSmart(Location loc, Type type, Exp exp)
{
	return buildCast(loc, copyTypeSmart(loc, type), exp);
}

Unary buildCastToBool(Location loc, Exp exp) { return buildCast(loc, buildBool(loc), exp); }
Unary buildCastToVoidPtr(Location loc, Exp exp) { return buildCast(loc, buildVoidPtr(loc), exp); }

/**
 * Builds an AddrOf expression.
 */
Unary buildAddrOf(Location loc, Exp exp)
{
	auto addr = new Unary();
	addr.location = loc;
	addr.op = Unary.Op.AddrOf;
	addr.value = exp;
	return addr;
}

/**
 * Builds a ExpReference and a AddrOf from a Variable.
 */
Unary buildAddrOf(Location loc, Variable var, string[] names...)
{
	return buildAddrOf(loc, buildExpReference(loc, var, names));
}

/**
 * Builds a Dereference expression.
 */
Unary buildDeref(Location loc, Exp exp)
{
	auto deref = new Unary();
	deref.location = loc;
	deref.op = Unary.Op.Dereference;
	deref.value = exp;
	return deref;
}

/**
 * Builds a New expression.
 */
Unary buildNew(Location loc, Type type, string name, Exp[] arguments...)
{
	auto new_ = new Unary();
	new_.location = loc;
	new_.op = Unary.Op.New;
	new_.type = buildTypeReference(loc, type, name);
// 	new_.type = type;
	new_.hasArgumentList = arguments.length > 0;
	new_.argumentList = arguments;
	return new_;
}

Unary buildNewSmart(Location loc, Type type, Exp[] arguments...)
{
	auto new_ = new Unary();
	new_.location = loc;
	new_.op = Unary.Op.New;
 	new_.type = copyTypeSmart(loc, type);
	new_.hasArgumentList = arguments.length > 0;
	new_.argumentList = arguments[0 .. arguments.length];
	return new_;
}

/**
 * Builds a typeid with type smartly.
 */
Typeid buildTypeidSmart(Location loc, Type type)
{
	auto t = new Typeid();
	t.location = loc;
	t.type = copyTypeSmart(loc, type);
	return t;
}

/**
 * Build a postfix Identifier expression.
 */
Postfix buildAccess(Location loc, Exp exp, string name)
{
	auto access = new Postfix();
	access.location = loc;
	access.op = Postfix.Op.Identifier;
	access.child = exp;
	access.identifier = new Identifier();
	access.identifier.location = loc;
	access.identifier.value = name;

	return access;
}

/**
 * Builds a postfix slice.
 */
Postfix buildSlice(Location loc, Exp child, Exp[] args...)
{
	auto slice = new Postfix();
	slice.location = loc;
	slice.op = Postfix.Op.Slice;
	slice.child = child;
	slice.arguments = args[0 .. args.length];

	return slice;
}

/**
 * Builds a postfix index.
 */
Postfix buildIndex(Location loc, Exp child, Exp arg)
{
	auto slice = new Postfix();
	slice.location = loc;
	slice.op = Postfix.Op.Index;
	slice.child = child;
	slice.arguments ~= arg;

	return slice;
}

/**
 * Builds a postfix call.
 */
Postfix buildCall(Location loc, Exp child, Exp[] args)
{
	auto call = new Postfix();
	call.location = loc;
	call.op = Postfix.Op.Call;
	call.child = child;
	call.arguments = args[0 .. args.length];

	return call;
}

Postfix buildMemberCall(Location loc, Exp child, ExpReference fn, string name, Exp[] args)
{
	auto lookup = new Postfix();
	lookup.location = loc;
	lookup.op = Postfix.Op.CreateDelegate;
	lookup.child = child;
	lookup.identifier = new Identifier();
	lookup.identifier.location = loc;
	lookup.identifier.value = name;
	lookup.memberFunction = fn;

	auto call = new Postfix();
	call.location = loc;
	call.op = Postfix.Op.Call;
	call.child = lookup;
	call.arguments = args;

	return call;
}

Postfix buildCreateDelegate(Location loc, Exp child, ExpReference fn)
{
	auto postfix = new Postfix();
	postfix.location = loc;
	postfix.op = Postfix.Op.CreateDelegate;
	postfix.child = child;
	postfix.memberFunction = fn;
	return postfix;
}

/**
 * Builds a postfix call.
 */
Postfix buildCall(Location loc, Declaration decl, Exp[] args, string[] names...)
{
	return buildCall(loc, buildExpReference(loc, decl, names), args);
}


/**
 * Builds an add BinOp.
 */
BinOp buildAdd(Location loc, Exp left, Exp right)
{
	return buildBinOp(loc, BinOp.Op.Add, left, right);
}

/**
 * Builds an assign BinOp.
 */
BinOp buildAssign(Location loc, Exp left, Exp right)
{
	return buildBinOp(loc, BinOp.Op.Assign, left, right);
}

/**
 * Builds an add-assign BinOp.
 */
BinOp buildAddAssign(Location loc, Exp left, Exp right)
{
	return buildBinOp(loc, BinOp.Op.AddAssign, left, right);
}

/**
 * Builds an BinOp.
 */
BinOp buildBinOp(Location loc, BinOp.Op op, Exp left, Exp right)
{
	auto binop = new BinOp();
	binop.location = loc;
	binop.op = op;
	binop.left = left;
	binop.right = right;
	return binop;
}

StatementExp buildStatementExp(Location loc)
{
	auto stateExp = new StatementExp();
	stateExp.location = loc;
	return stateExp;
}

StatementExp buildStatementExp(Location loc, Node[] stats, Exp exp)
{
	auto stateExp = buildStatementExp(loc);
	stateExp.statements = stats;
	stateExp.exp = exp;
	return stateExp;
}

FunctionParam buildFunctionParam(Location loc, size_t index, string name, Function fn)
{
	auto fparam = new FunctionParam();
	fparam.location = loc;
	fparam.index = index;
	fparam.name = name;
	fparam.fn = fn;
	return fparam;
}

/**
 * Adds a variable argument to a function, also adds it to the scope.
 */
FunctionParam addParam(Location loc, Function fn, Type type, string name)
{
	auto var = buildFunctionParam(loc, fn.type.params.length, name, fn);

	fn.type.params ~= type;

	fn.params ~= var;
	fn.myScope.addValue(var, name);

	return var;
}

/**
 * Adds a variable argument to a function, also adds it to the scope.
 */
FunctionParam addParamSmart(Location loc, Function fn, Type type, string name)
{
	return addParam(loc, fn, copyTypeSmart(loc, type), name);
}

/**
 * Builds a variable statement smartly, inserting at the end of the
 * block statements and inserting it in the scope.
 */
Variable buildVarStatSmart(Location loc, BlockStatement block, Scope _scope, Type type, string name)
{
	auto var = buildVariableSmart(loc, type, Variable.Storage.Function, name);
	block.statements ~= var;
	_scope.addValue(var, name);
	return var;
}

/**
 * Build an exp statement and add it to a StatementExp.
 */
ExpStatement buildExpStat(Location loc, StatementExp stat, Exp exp)
{
	auto ret = new ExpStatement();
	ret.location = loc;
	ret.exp = exp;

	stat.statements ~= ret;

	return ret;
}

StatementExp buildVaArgCast(Location loc, VaArgExp vaexp)
{
	auto sexp = new StatementExp();
	sexp.location = loc;

	auto ptrToPtr = buildVariableSmart(loc, buildPtrSmart(loc, buildVoidPtr(loc)), Variable.Storage.Function, "ptrToPtr");
	ptrToPtr.assign = buildAddrOf(loc, vaexp.arg);
	sexp.statements ~= ptrToPtr;

	auto cpy = buildVariableSmart(loc, buildVoidPtr(loc), Variable.Storage.Function, "cpy");
	cpy.assign = buildDeref(loc, buildExpReference(loc, ptrToPtr));
	sexp.statements ~= cpy;

	auto vlderef = buildDeref(loc, buildExpReference(loc, ptrToPtr));
	auto tid = buildTypeidSmart(loc, vaexp.type);
	auto sz = buildAccess(loc, tid, "size");
	auto assign = buildAddAssign(loc, vlderef, sz);
	buildExpStat(loc, sexp, assign);

	auto ptr = buildPtrSmart(loc, vaexp.type);
	auto _cast = buildCastSmart(loc, ptr, buildExpReference(loc, cpy));
	auto deref = buildDeref(loc, _cast);
	sexp.exp = deref;

	return sexp;
}

Exp buildVaArgStart(Location loc, Exp vlexp, Exp argexp)
{
	return buildAssign(loc, buildDeref(loc, vlexp), argexp);
}

Exp buildVaArgEnd(Location loc, Exp vlexp)
{
	return buildAssign(loc, buildDeref(loc, vlexp), buildConstantNull(loc, buildVoidPtr(loc)));
}

StatementExp buildInternalArrayLiteralSmart(Location loc, Type atype, Exp[] exps)
{
	assert(atype.nodeType == NodeType.ArrayType);
	auto sexp = new StatementExp();
	sexp.location = loc;
	auto var = buildVariableSmart(loc, copyTypeSmart(loc, atype), Variable.Storage.Function, "array");
	sexp.statements ~= var;
	auto _new = buildNewSmart(loc, atype, buildConstantUint(loc, cast(uint) exps.length));
	auto vassign = buildAssign(loc, buildExpReference(loc, var), _new);
	buildExpStat(loc, sexp, vassign);
	foreach (i, exp; exps) {
		auto slice = buildIndex(loc, buildExpReference(loc, var), buildConstantUint(loc, cast(uint) i));
		auto assign = buildAssign(loc, slice, exp);
		buildExpStat(loc, sexp, assign);
	}
	sexp.exp = buildExpReference(loc, var, var.name);
	return sexp;
}

StatementExp buildInternalArrayLiteralSliceSmart(Location loc, Type atype, Type[] types, int[] sizes, int totalSize, Function memcpyFn, Exp[] exps)
{
	assert(atype.nodeType == NodeType.ArrayType);
	auto sexp = new StatementExp();
	sexp.location = loc;
	auto var = buildVariableSmart(loc, copyTypeSmart(loc, atype), Variable.Storage.Function, "array");

	sexp.statements ~= var;
	auto _new = buildNewSmart(loc, atype, buildConstantUint(loc, cast(uint) totalSize));
	auto vassign = buildAssign(loc, buildExpReference(loc, var), _new);
	buildExpStat(loc, sexp, vassign);

	int offset;
	foreach (i, exp; exps) {
		auto evar = buildVariableSmart(loc, types[i], Variable.Storage.Function, "exp"); 
		sexp.statements ~= evar;
		auto evassign = buildAssign(loc, buildExpReference(loc, evar), exp);
		buildExpStat(loc, sexp, evassign);

		Exp dst = buildAdd(loc, buildAccess(loc, buildExpReference(loc, var), "ptr"), buildConstantUint(loc, cast(uint) offset));
		Exp src = buildCastToVoidPtr(loc, buildAddrOf(loc, buildExpReference(loc, evar)));
		Exp len = buildConstantUint(loc, cast(uint) sizes[i]);
		Exp aln = buildConstantInt(loc, 0);
		Exp vol = buildConstantBool(loc, false);
		auto args = new Exp[](5);
		args[0] = dst; args[1] = src; args[2] = len;
		args[3] = aln; args[4] = vol;
		auto call = buildCall(loc, buildExpReference(loc, memcpyFn), args);
		buildExpStat(loc, sexp, call);
		offset += sizes[i];
	}
	sexp.exp = buildExpReference(loc, var, var.name);
	return sexp;
}
/**
 * Build an exp statement and add it to a block.
 */
ExpStatement buildExpStat(Location loc, BlockStatement block, Exp exp)
{
	auto ret = new ExpStatement();
	ret.location = loc;
	ret.exp = exp;

	block.statements ~= ret;

	return ret;
}


/**
 * Build an exp statement without inserting it anywhere.
 */
ExpStatement buildExpStat(Location loc, Exp exp)
{
	auto ret = new ExpStatement();
	ret.location = loc;
	ret.exp = exp;
	return ret;
}


/**
 * Build an if statement.
 */
IfStatement buildIfStat(Location loc, BlockStatement block, Exp exp,
                           BlockStatement thenState, BlockStatement elseState = null, string autoName = "")
{
	auto ret = new IfStatement();
	ret.location = loc;
	ret.exp = exp;
	ret.thenState = thenState;
	ret.elseState = elseState;
	ret.autoName = autoName;

	block.statements ~= ret;

	return ret;
}

/**
 * Build an if statement.
 */
IfStatement buildIfStat(Location loc, StatementExp statExp, Exp exp,
                           BlockStatement thenState, BlockStatement elseState = null, string autoName = "")
{
	auto ret = new IfStatement();
	ret.location = loc;
	ret.exp = exp;
	ret.thenState = thenState;
	ret.elseState = elseState;
	ret.autoName = autoName;

	statExp.statements ~= ret;

	return ret;
}

/**
 * Build a block statement.
 */
BlockStatement buildBlockStat(Location loc, Node introducingNode, Scope _scope, Node[] statements...)
{
	auto ret = new BlockStatement();
	ret.location = loc;
	ret.statements = statements;
	ret.myScope = new Scope(_scope, introducingNode, "block");

	return ret;
}


/**
 * Build a return statement.
 */
ReturnStatement buildReturnStat(Location loc, BlockStatement block, Exp exp = null)
{
	auto ret = new ReturnStatement();
	ret.location = loc;
	ret.exp = exp;

	block.statements ~= ret;

	return ret;
}

/**
 * Builds a completely useable Function and insert it into the
 * various places it needs to be inserted.
 */
Function buildFunction(Location loc, TopLevelBlock tlb, Scope _scope, string name, bool buildBody = true)
{
	auto fn = new Function();
	fn.name = name;
	fn.location = loc;
	fn.kind = Function.Kind.Function;
	fn.myScope = new Scope(_scope, fn, fn.name);

	fn.type = new FunctionType();
	fn.type.location = loc;
	fn.type.ret = new PrimitiveType(PrimitiveType.Kind.Void);
	fn.type.ret.location = loc;

	if (buildBody) {
		fn._body = new BlockStatement();
		fn._body.location = loc;
		fn._body.myScope = new Scope(fn.myScope, fn._body, name);
	}

	// Insert the struct into all the places.
	_scope.addFunction(fn, fn.name);
	tlb.nodes ~= fn;
	return fn;
}

/**
 * Builds a alias from a string and a Identifier.
 */
Alias buildAliasSmart(Location loc, string name, Identifier i)
{
	auto a = new Alias();
	a.name = name;
	a.location = loc;
	a.id = buildQualifiedNameSmart(i);
	return a;
}

/**
 * Builds a alias from two strings.
 */
Alias buildAlias(Location loc, string name, string from)
{
	auto a = new Alias();
	a.name = name;
	a.location = loc;
	a.id = buildQualifiedName(loc, from);
	return a;
}

/**
 * Builds a completely useable struct and insert it into the
 * various places it needs to be inserted.
 *
 * The members list is used directly in the new struct; be wary not to duplicate IR nodes.
 */
Struct buildStruct(Location loc, TopLevelBlock tlb, Scope _scope, string name, Variable[] members...)
{
	auto s = new Struct();
	s.name = name;
	s.myScope = new Scope(_scope, s, name);
	s.location = loc;

	s.members = new TopLevelBlock();
	s.members.location = loc;

	foreach (member; members) {
		s.members.nodes ~= member;
		s.myScope.addValue(member, member.name);
	}

	// Insert the struct into all the places.
	_scope.addType(s, s.name);
	tlb.nodes ~= s;
	return s;
}

/**
 * Builds an IR complete, but semantically unfinished struct. i.e. it has no scope and isn't inserted anywhere.
 * The members list is used directly in the new struct; be wary not to duplicate IR nodes.
 */
Struct buildStruct(Location loc, string name, Variable[] members...)
{
	auto s = new Struct();
	s.name = name;
	s.location = loc;

	s.members = new TopLevelBlock();
	s.members.location = loc;

	foreach (member; members) {
		s.members.nodes ~= member;
	}

	return s;
}

/**
 * Add a variable to a pre-built struct.
 */
void addVarToStructSmart(Struct _struct, Variable var)
{
	auto cvar = buildVariableSmart(var.location, var.type, Variable.Storage.Field, var.name);
	_struct.members.nodes ~= cvar;
	_struct.myScope.addValue(cvar, cvar.name);
}

/**
 * If t is a class, or a typereference to a class, returns the
 * class. Otherwise, returns null.
 */
Class getClass(Type t)
{
	auto asClass = cast(Class) t;
	if (asClass !is null) {
		return asClass;
	}
	auto asTR = cast(TypeReference) t;
	if (asTR is null) {
		return null;
	}
	asClass = cast(Class) asTR.type;
	return asClass;
}

Type buildStaticArrayTypeSmart(Location loc, size_t length, Type base)
{
	auto sa = new StaticArrayType();
	sa.location = loc;
	sa.length = length;
	sa.base = copyTypeSmart(loc, base);
	return sa;
}

Type buildAATypeSmart(Location loc, Type key, Type value)
{
	auto aa = new AAType();
	aa.location = loc;
	aa.key = copyTypeSmart(loc, key);
	aa.value = copyTypeSmart(loc, value);
	return aa;
}

/*
 * Functions who takes the location from the given exp.
 */
Unary buildCastSmart(Type type, Exp exp) { return buildCastSmart(exp.location, type, exp); }
Unary buildAddrOf(Exp exp) { return buildAddrOf(exp.location, exp); }
Unary buildCastToBool(Exp exp) { return buildCastToBool(exp.location, exp); }

Type buildSetType(Location loc, Function[] functions)
{
	assert(functions.length > 0);
	if (functions.length == 1) {
		return functions[0].type;
	}

	auto set = new FunctionSetType();
	set.location = loc;
	set.set = cast(FunctionSet) buildSet(loc, functions);
	assert(set.set !is null);
	assert(set.set.functions.length > 0);
	return set;
}

Declaration buildSet(Location loc, Function[] functions, ExpReference eref = null)
{
	assert(functions.length > 0);
	if (functions.length == 1) {
		return functions[0];
	}

	auto set = new FunctionSet();
	set.functions = functions;
	set.location = loc;
	set.reference = eref;
	assert(set.functions.length > 0);
	return set;
}

Type stripStorage(Type type)
{
	auto storage = cast(StorageType) type;
	while (storage !is null) {
		type = storage.base;
		storage = cast(StorageType) type;
	}
	return type;
}

Type deepStripStorage(Type type)
{
	auto ptr = cast(PointerType) type;
	if (ptr !is null) {
		ptr.base = deepStripStorage(ptr.base);
		return ptr;
	}

	auto arr = cast(ArrayType) type;
	if (arr !is null) {
		arr.base = deepStripStorage(arr.base);
		return arr;
	}

	auto aa = cast(AAType) type;
	if (aa !is null) {
		aa.value = deepStripStorage(aa.value);
		aa.key = deepStripStorage(aa.key);
		return aa;
	}

	auto ct = cast(CallableType) type;
	if (ct !is null) {
		ct.ret = deepStripStorage(ct.ret);
		foreach (ref param; ct.params) {
			param = deepStripStorage(param);
		}
		return ct;
	}

	auto storage = cast(StorageType) type;
	if (storage !is null) {
		storage.base = stripStorage(storage.base);
		return storage.base;
	}

	return type;
}

/// Returns the base of consecutive pointers. e.g. 'int***' returns 'int'.
Type realBase(PointerType ptr)
{
	Type base;
	do {
		base = ptr.base;
		ptr = cast(PointerType) base;
	} while (ptr !is null);
	return base;
}

