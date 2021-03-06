// Copyright © 2012-2013, Bernard Helyer.  All rights reserved.
// Copyright © 2012-2013, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.semantic.extyper;

import watt.conv;
import watt.text.format;

import ir = volt.ir.ir;
import volt.ir.util;
import volt.ir.copy;

import volt.errors;
import volt.interfaces;
import volt.util.string;
import volt.token.location;
import volt.visitor.visitor;
import volt.visitor.scopemanager;
import volt.visitor.prettyprinter;
import volt.visitor.iexpreplace;
import volt.semantic.userattrresolver;
import volt.semantic.classify;
import volt.semantic.classresolver;
import volt.semantic.lookup;
import volt.semantic.typer;
import volt.semantic.util;
import volt.semantic.ctfe;
import volt.semantic.overload;
import volt.semantic.nested;
import volt.semantic.context;

/**
 * This handles the auto that has been filled in, removing the auto storage.
 */
void replaceStorageIfNeeded(ref ir.Type type)
{
	auto storage = cast(ir.StorageType) type;
	if (storage !is null && storage.type == ir.StorageType.Kind.Auto && storage.base !is null) {
		type = storage.base;
	}
}

/**
 * This handles implicitly typing null.
 * Generic function used by assign and other functions.
 */
bool handleIfNull(Context ctx, ir.Type left, ref ir.Exp right)
{
	auto rightType = getExpType(ctx.lp, right, ctx.current);
	if (rightType.nodeType != ir.NodeType.NullType) {
		return false;
	}

	return handleNull(left, right, rightType) !is null;
}

/**
 * This handles implicitly typing a struct literal.
 *
 * While generic currently only used by extypeAssign.
 */
bool handleIfStructLiteral(Context ctx, ir.Type left, ref ir.Exp right)
{
	auto asLit = cast(ir.StructLiteral) right;
	if (asLit is null)
		return false;

	assert(asLit !is null);

	auto asStruct = cast(ir.Struct) realType(left);
	if (asStruct is null) {
		throw makeBadImplicitCast(right, getExpType(ctx.lp, right, ctx.current), left);
	}

	ir.Type[] types = getStructFieldTypes(asStruct);

	if (types.length < asLit.exps.length) {
		throw makeBadImplicitCast(right, getExpType(ctx.lp, right, ctx.current), left);
	}

	foreach (i, ref sexp; asLit.exps) {
		extypeAssign(ctx, sexp, types[i]);
	}

	asLit.type = buildTypeReference(right.location, asStruct, asStruct.name);
	return true;
}

/**
 * Implicitly convert PrimitiveTypes to bools for 'if' and friends.
 */
void extypeCastToBool(Context ctx, ref ir.Exp exp)
{
	auto t = getExpType(ctx.lp, exp, ctx.current);
	if (t.nodeType == ir.NodeType.PrimitiveType) {
		auto asPrimitive = cast(ir.PrimitiveType) realType(t);
		if (asPrimitive.type == ir.PrimitiveType.Kind.Bool) {
			return;
		}
	}
	exp = buildCastToBool(exp.location, exp);
}

/**
 * This deals with one side of an assign statement being 
 * a storage type and the other not.
 * It allows scope and const to decay if the left hand side
 * isn't mutably indirect. It also allows types to be converted
 * into scoped ones.
 */
void extypeAssignHandleStorage(Context ctx, ref ir.Exp exp, ir.Type ltype)
{
	auto rtype = realType(getExpType(ctx.lp, exp, ctx.current));
	ltype = realType(ltype);
	if (ltype.nodeType != ir.NodeType.StorageType &&
	    rtype.nodeType == ir.NodeType.StorageType) {
		auto asStorageType = cast(ir.StorageType) rtype;
		assert(asStorageType !is null);
		if (asStorageType.type == ir.StorageType.Kind.Scope) {
			if (mutableIndirection(asStorageType.base)) {
				throw makeBadImplicitCast(exp, rtype, ltype);
			}
			exp = buildCastSmart(asStorageType.base, exp);
		}

		if (effectivelyConst(rtype)) {
			if (!mutableIndirection(asStorageType.base)) {
				exp = buildCastSmart(asStorageType.base, exp);
			} else {
				throw makeBadImplicitCast(exp, rtype, ltype);
			}
		}
	} else if (ltype.nodeType == ir.NodeType.StorageType &&
	           rtype.nodeType != ir.NodeType.StorageType) {
		auto asStorageType = cast(ir.StorageType) ltype;
		/* Scope is always the first StorageType, so we don't have to
		 * worry about StorageType chains.
		 */
		if (asStorageType.type == ir.StorageType.Kind.Scope) {
			exp = buildCastSmart(asStorageType, exp);
		}
	}
}

/**
 * This handles implicitly casting a const type to a mutable type,
 * if the underlying type has no mutable indirection.
 */
void extypePassHandleStorage(Context ctx, ref ir.Exp exp, ir.Type ltype)
{
	auto rtype = realType(getExpType(ctx.lp, exp, ctx.current));
	ltype = realType(ltype);
	if (ltype.nodeType != ir.NodeType.StorageType &&
	    rtype.nodeType == ir.NodeType.StorageType) {
		auto asStorageType = cast(ir.StorageType) rtype;
		assert(asStorageType !is null);

		if (effectivelyConst(rtype)) {
			if (!mutableIndirection(asStorageType.base)) {
				exp = buildCastSmart(asStorageType.base, exp);
			} else {
				throw makeBadImplicitCast(exp, rtype, ltype);
			}
		}
	}
}


/**
 * Forbids mutably indirect types being implicitly casted to scope.
 */
void rejectBadScopeAssign(Context ctx, ref ir.Exp exp, ir.Type type)
{
	auto storage = cast(ir.StorageType) realType(type);
	if (storage is null) {
		return;
	}
	if (mutableIndirection(storage.base)) {
		if (!ctx.isVarAssign || (ctx.current.node.nodeType != ir.NodeType.Function && ctx.current.node.nodeType != ir.NodeType.BlockStatement)) {
			throw makeBadImplicitCast(exp, type, storage);
		}
	}
}

void extypeAssignTypeReference(Context ctx, ref ir.Exp exp, ir.TypeReference tr)
{
	extypeAssign(ctx, exp, tr.type);
}

void stripPointerBases(ir.Type toType, ref uint flag)
{
	switch (toType.nodeType) {
	case ir.NodeType.PointerType:
		auto ptr = cast(ir.PointerType) toType;
		assert(ptr !is null);
		ptr.base = flagitiseStorage(ptr.base, flag);
		stripPointerBases(ptr.base, flag);
		break;
	default:
		break;
	}
}

void stripArrayBases(ir.Type toType, ref uint flag)
{
	switch (toType.nodeType) {
	case ir.NodeType.ArrayType:
		auto arr = cast(ir.ArrayType) toType;
		assert(arr !is null);
		arr.base = flagitiseStorage(arr.base, flag);
		stripArrayBases(arr.base, flag);
		break;
	default:
		break;
	}
}

void appendDefaultArguments(Context ctx, ir.Location loc, ref ir.Exp[] arguments, ir.Function fn)
{
	if (fn !is null && arguments.length < fn.params.length) {
		ir.Exp[] overflow;
		foreach (p; fn.params[arguments.length .. $]) {
			if (p.assign is null) {
				throw makeExpected(loc, "default argument");
			}
			overflow ~= p.assign;
		}
		auto oldLength = arguments.length;
		foreach (i, ee; overflow) {
			auto constant = cast(ir.Constant) ee;
			if (constant is null) {
				auto texp = cast(ir.TokenExp) ee;
				assert(texp !is null);
				texp.location = loc;
				arguments ~= texp;
			} else {
				arguments ~= copyExp(loc, ee);
			}
			acceptExp(arguments[$-1], ctx.etyper);
		}
	}
}

/**
 * Handles implicit pointer casts. To void*, immutable(T)* to const(T)*
 * T* to const(T)* and the like.
 */
void extypeAssignPointerType(Context ctx, ref ir.Exp exp, ir.PointerType ptr, uint flag)
{
	ir.PointerType pcopy = cast(ir.PointerType) copyTypeSmart(exp.location, ptr);
	assert(pcopy !is null);
	stripPointerBases(pcopy, flag);

	// string literals implicitly convert to typeof(string.ptr)
	auto constant = cast(ir.Constant) exp;
	if (constant !is null && constant._string.length != 0) {
		exp = buildAccess(exp.location, exp, "ptr");
	}

	auto type = ctx.overrideType !is null ? ctx.overrideType : realType(getExpType(ctx.lp, exp, ctx.current));

	auto storage = cast(ir.StorageType) type;
	if (storage !is null) {
		type = storage.base;
	}

	auto rp = cast(ir.PointerType) type;
	if (rp is null) {
		throw makeBadImplicitCast(exp, type, pcopy);
	}
	ir.PointerType rcopy = cast(ir.PointerType) copyTypeSmart(exp.location, rp);
	assert(rcopy !is null);


	auto pbase = realBase(pcopy);
	auto rbase = realBase(rcopy);
	uint rflag, raflag;
	flagitiseStorage(rcopy, rflag);
	rcopy.base = flagitiseStorage(rp.base, raflag);
	rflag |= raflag;
	uint aflag;
	pcopy.base = flagitiseStorage(ptr.base, aflag);
	flag |= aflag;

	if (typesEqual(pcopy, rcopy)) {
		return;
	}

	if (pbase.nodeType == ir.NodeType.PrimitiveType) {
		auto asPrimitive = cast(ir.PrimitiveType) pbase;
		assert(asPrimitive !is null);
		if (asPrimitive.type == ir.PrimitiveType.Kind.Void) {
			exp = buildCastSmart(pcopy, exp);
			return;
		}
	}

	if (flag & ir.StorageType.STORAGE_CONST && !(rflag & ir.StorageType.STORAGE_SCOPE)) {
		exp = buildCastSmart(pcopy, exp);
		return;
	}

	if (rflag & ir.StorageType.STORAGE_IMMUTABLE && rflag & ir.StorageType.STORAGE_CONST) {
		exp = buildCastSmart(pcopy, exp);
		return;
	}

	throw makeBadImplicitCast(exp, type, pcopy);
}

/**
 * Implicit primitive casts (smaller to larger).
 */
void extypeAssignPrimitiveType(Context ctx, ref ir.Exp exp, ir.PrimitiveType lprim)
{
	auto rtype = getExpType(ctx.lp, exp, ctx.current);
	auto rprim = cast(ir.PrimitiveType) realType(rtype, true, true);
	if (rprim is null) {
		throw makeBadImplicitCast(exp, rtype, lprim);
	}

	if (typesEqual(lprim, rprim)) {
		return;
	}

	auto lsize = size(lprim.type);
	auto rsize = size(rprim.type);

	auto lunsigned = isUnsigned(lprim.type);
	auto runsigned = isUnsigned(rprim.type);

	if (lunsigned != runsigned && !fitsInPrimitive(lprim, exp) && rsize >= lsize) {
		throw makeBadImplicitCast(exp, rprim, lprim);
	}

	if (rsize > lsize && !fitsInPrimitive(lprim, exp)) {
		throw makeBadImplicitCast(exp, rprim, lprim);
	}

	exp = buildCastSmart(lprim, exp);
}

/**
 * Handles converting child classes to parent classes.
 */
void extypeAssignClass(Context ctx, ref ir.Exp exp, ir.Class _class)
{
	auto type = realType(getExpType(ctx.lp, exp, ctx.current));
	assert(type !is null);

	auto rightClass = cast(ir.Class) type;
	if (rightClass is null) {
		throw makeBadImplicitCast(exp, type, _class);
	}
	ctx.lp.resolve(rightClass);

	// Check for converting child classes into parent classes.
	if (_class !is null && rightClass !is null) {
		if (inheritsFrom(rightClass, _class)) {
			exp = buildCastSmart(exp.location, _class, exp);
			return;
		}
	}

	if (_class !is rightClass) {
		throw makeBadImplicitCast(exp, rightClass, _class);
	}
}

void extypeAssignEnum(Context ctx, ref ir.Exp exp, ir.Enum e)
{
	auto rtype = getExpType(ctx.lp, exp, ctx.current);
	if (typesEqual(e, rtype)) {
		return;
	}

	// TODO: This might need to be smarter.
	extypeAssignDispatch(ctx, exp, e.base);
}


/**
 * Handles assigning an overloaded function to a delegate.
 */
void extypeAssignCallableType(Context ctx, ref ir.Exp exp, ir.CallableType ctype)
{
	auto rtype = ctx.overrideType !is null ? ctx.overrideType : realType(getExpType(ctx.lp, exp, ctx.current));
	if (typesEqual(ctype, rtype)) {
		return;
	}
	if (rtype.nodeType == ir.NodeType.FunctionSetType) {
		auto fset = cast(ir.FunctionSetType) rtype;
		auto fn = selectFunction(ctx.lp, fset.set, ctype.params, exp.location);
		auto eRef = buildExpReference(exp.location, fn, fn.name);
		fset.set.reference = eRef;
		exp = eRef;
		replaceExpReferenceIfNeeded(ctx, null, exp, eRef);
		extypeAssignCallableType(ctx, exp, ctype);
		return;
	}
	throw makeBadImplicitCast(exp, rtype, ctype);
}

/**
 * Handles casting arrays of non mutably indirect types with
 * differing storage types.
 */
void extypeAssignArrayType(Context ctx, ref ir.Exp exp, ir.ArrayType atype, ref uint flag)
{
	auto acopy = copyTypeSmart(exp.location, atype);
	stripArrayBases(acopy, flag);
	auto rtype = ctx.overrideType !is null ? ctx.overrideType : realType(getExpType(ctx.lp, exp, ctx.current));
	auto rarr = cast(ir.ArrayType) copyTypeSmart(exp.location, rtype);
	uint rflag;
	if (rarr !is null) {
		stripArrayBases(rarr, rflag);
	}
	bool badImmutable = (flag & ir.StorageType.STORAGE_IMMUTABLE) != 0 && (rflag & ir.StorageType.STORAGE_IMMUTABLE) == 0;
	if (typesEqual(acopy, rarr !is null ? rarr : rtype) && 
		!badImmutable && (flag & ir.StorageType.STORAGE_SCOPE) == 0) {
		return;
	}

	auto ctype = cast(ir.CallableType) atype;
	if (ctype !is null && ctype.homogenousVariadic && rarr is null) {
		return;
	}

	auto aclass = cast(ir.Class) realType(atype.base);
	ir.Class rclass;
	if (rarr !is null) {
		rclass = cast(ir.Class) realType(rarr.base);
	}
	if (rclass !is null) {
		if (inheritsFrom(rclass, aclass)) {
			exp = buildCastSmart(exp.location, buildArrayType(exp.location, aclass), exp);
			return;
		}
	}

	throw makeBadImplicitCast(exp, rtype, atype);
}

void extypeAssignAAType(Context ctx, ref ir.Exp exp, ir.AAType aatype)
{
	auto rtype = ctx.overrideType !is null ? ctx.overrideType : getExpType(ctx.lp, exp, ctx.current);
	if (exp.nodeType == ir.NodeType.AssocArray && typesEqual(aatype, rtype)) {
		return;
	}

	if (exp.nodeType == ir.NodeType.ArrayLiteral &&
	    (cast(ir.ArrayLiteral)exp).values.length == 0) {
		auto aa = new ir.AssocArray();
		aa.location = exp.location;
		aa.type = copyTypeSmart(exp.location, aatype);
		exp = aa;
		return;
	}

	if (rtype.nodeType == ir.NodeType.AAType) {
	    throw makeBadAAAssign(exp.location);
	}

	throw makeBadImplicitCast(exp, rtype, aatype);
}

ir.Type flagitiseStorage(ir.Type type, ref uint flag)
{
	auto storage = cast(ir.StorageType) type;
	while (storage !is null) {
		final switch (storage.type) with (ir.StorageType) {
		case Kind.Auto:
			flag |= STORAGE_AUTO;
			break;
		case Kind.Const:
			flag |= STORAGE_CONST;
			break;
		case Kind.Immutable:
			flag |= STORAGE_IMMUTABLE;
			break;
		case Kind.Scope:
			flag |= STORAGE_SCOPE;
			break;
		case Kind.Ref:
			flag |= STORAGE_REF;
			break;
		case Kind.Out:
			flag |= STORAGE_OUT;
			break;
		}
		type = storage.base;
		storage = cast(ir.StorageType) storage.base;
	}
	return type;
}



void handleAssign(Context ctx, ref ir.Type toType, ref ir.Exp exp, ref uint toFlag)
{
	auto rtype = getExpType(ctx.lp, exp, ctx.current);
	auto storage = cast(ir.StorageType) toType;
	if (storage !is null && storage.base is null) {
		if (rtype.nodeType == ir.NodeType.FunctionSetType) {
			throw makeCannotInfer(exp.location);
		}
		storage.base = copyTypeSmart(exp.location, rtype);
	}
	auto originalRtype = rtype;
	auto originalTo = toType;
	toType = flagitiseStorage(toType, toFlag);
	uint rflag;
	rtype = flagitiseStorage(rtype, rflag);
	if ((toFlag & ir.StorageType.STORAGE_SCOPE) != 0 && ctx.isVarAssign) {
		exp = buildCastSmart(exp.location, toType, exp);
	} else if ((toFlag & ir.StorageType.STORAGE_SCOPE) != 0 && (rflag & ir.StorageType.STORAGE_SCOPE) == 0 && mutableIndirection(toType)) {
		throw makeBadImplicitCast(exp, originalRtype, originalTo);
	} else if ((rflag & ir.StorageType.STORAGE_CONST) != 0 && !(toFlag & ir.StorageType.STORAGE_CONST) && mutableIndirection(toType)) {
		throw makeBadImplicitCast(exp, originalRtype, originalTo);
	} else if (mutableIndirection(toType) && (rflag & ir.StorageType.STORAGE_SCOPE) != 0) {
		throw makeBadImplicitCast(exp, originalRtype, originalTo);
	}
}

void extypeAssignDispatch(Context ctx, ref ir.Exp exp, ir.Type type)
{
	uint flag;
	handleAssign(ctx, type, exp, flag);
	switch (type.nodeType) {
	case ir.NodeType.StorageType:
		auto storage = cast(ir.StorageType) type;
		extypeAssignDispatch(ctx, exp, storage.base);
		break;
	case ir.NodeType.TypeReference:
		auto tr = cast(ir.TypeReference) type;
		extypeAssignTypeReference(ctx, exp, tr);
		break;
	case ir.NodeType.PointerType:
		auto ptr = cast(ir.PointerType) type;
		extypeAssignPointerType(ctx, exp, ptr, flag);
		break;
	case ir.NodeType.PrimitiveType:
		auto prim = cast(ir.PrimitiveType) type;
		extypeAssignPrimitiveType(ctx, exp, prim);
		break;
	case ir.NodeType.Class:
		auto _class = cast(ir.Class) type;
		extypeAssignClass(ctx, exp, _class);
		break;
	case ir.NodeType.Enum:
		auto e = cast(ir.Enum) type;
		extypeAssignEnum(ctx, exp, e);
		break;
	case ir.NodeType.FunctionType:
	case ir.NodeType.DelegateType:
		auto ctype = cast(ir.CallableType) type;
		extypeAssignCallableType(ctx, exp, ctype);
		break;
	case ir.NodeType.ArrayType:
		auto atype = cast(ir.ArrayType) type;
		extypeAssignArrayType(ctx, exp, atype, flag);
		break;
	case ir.NodeType.AAType:
		auto aatype = cast(ir.AAType) type;
		extypeAssignAAType(ctx, exp, aatype);
		break;
	case ir.NodeType.Struct:
	case ir.NodeType.Union:
		auto rtype = getExpType(ctx.lp, exp, ctx.current);
		if (typesEqual(type, rtype)) {
			return;
		}
		throw makeBadImplicitCast(exp, rtype, type);
	default:
		throw panicUnhandled(exp, to!string(type.nodeType));
	}
}

void extypePass(Context ctx, ref ir.Exp exp, ir.Type type)
{
	ensureResolved(ctx.lp, ctx.current, type);
	auto storage = cast(ir.StorageType) type;
	if (storage !is null && storage.type == ir.StorageType.Kind.Scope) {
		type = storage.base;
	}
	extypeAssign(ctx, exp, type);
}

void extypeAssign(Context ctx, ref ir.Exp exp, ir.Type type)
{
	ensureResolved(ctx.lp, ctx.current, type);
	if (handleIfStructLiteral(ctx, type, exp)) return;
	if (handleIfNull(ctx, type, exp)) return;

	extypeAssignDispatch(ctx, exp, type);
}

/**
 * If qname has a child of name leaf, returns an expression looking it up.
 * Otherwise, null is returned.
 */
ir.Exp withLookup(Context ctx, ref ir.Exp exp, ir.Scope current, string leaf, ir.Postfix pleaf = null)
{
	ir.Exp access = buildAccess(exp.location, copyExp(exp), leaf);
	ir.Class _class;
	string emsg;
	ir.Scope eScope;
	auto type = realType(getExpType(ctx.lp, exp, current), false, true);
	if (exp.nodeType == ir.NodeType.Postfix) {
		retrieveScope(ctx.lp, type, cast(ir.Postfix)exp, eScope, _class, emsg);
	} else {
		retrieveScope(ctx.lp, type, cast(ir.Postfix)access, eScope, _class, emsg);
	}
	if (eScope is null) {
		throw makeBadWithType(exp.location);
	}
	auto store = lookupOnlyThisScope(ctx.lp, eScope, exp.location, leaf);
	if (store is null) {
		return null;
	}
	if (exp.nodeType == ir.NodeType.IdentifierExp) {
		extypeLeavePostfix(ctx, access, cast(ir.Postfix) access);
	}
	return access;
}

/**
 * Replace IdentifierExps with ExpReferences.
 */
void extypeIdentifierExp(Context ctx, ref ir.Exp e, ir.IdentifierExp i)
{
	auto current = i.globalLookup ? getModuleFromScope(ctx.current).myScope : ctx.current;

	// Rewrite expressions that rely on a with block lookup.
	ir.Exp rewriteExp;
	foreach (withStatement; current.withStatements) {
		auto withExp = withStatement.exp;
		auto _rewriteExp = withLookup(ctx, withExp, current, i.value);
		if (_rewriteExp is null) {
			continue;
		}
		if (rewriteExp !is null) {
			throw makeWithCreatesAmbiguity(withExp.location);
		}
		rewriteExp = _rewriteExp;
		// Continue to ensure no ambiguity.
	}
	if (rewriteExp !is null) {
		auto store = lookup(ctx.lp, current, i.location, i.value);
		if (store !is null) {
			throw makeWithCreatesAmbiguity(i.location);
		}
		e = rewriteExp;
		return;
	}
	// With rewriting is completed after this point, and regular lookup logic resumes.

	if (i.type is null) {
		i.type = declTypeLookup(i.location, ctx.lp, current, i.value);
	}

	auto store = lookup(ctx.lp, current, i.location, i.value);
	if (store is null) {
		throw makeFailedLookup(i, i.value);
	}

	auto _ref = new ir.ExpReference();
	_ref.idents ~= i.value;
	_ref.location = i.location;

	final switch (store.kind) with (ir.Store.Kind) {
	case Value:
		auto var = cast(ir.Variable) store.node;
		assert(var !is null);
		if (!var.hasBeenDeclared && var.storage == ir.Variable.Storage.Function) {
			throw makeUsedBeforeDeclared(e, var);
		}
		_ref.decl = var;
		e = _ref;
		tagNestedVariables(ctx, var, store, e);
		return;
	case FunctionParam:
		auto fp = cast(ir.FunctionParam) store.node;
		assert(fp !is null);
		_ref.decl = fp;
		e = _ref;
		return;
	case Function:
		foreach (fn; store.functions) {
			if (fn.nestedHiddenParameter !is null && store.functions.length > 1) {
				throw makeCannotOverloadNested(fn, fn);
			} else if (fn.nestedHiddenParameter !is null) {
				_ref.decl = store.functions[0];
				e = _ref;
				return;
			}
		}
		_ref.decl = buildSet(i.location, store.functions);
		e = _ref;
		return;
	case EnumDeclaration:
		auto ed = cast(ir.EnumDeclaration) store.node;
		assert(ed !is null);
		assert(ed.assign !is null);
		e = copyExp(ed.assign);
		return;
	case Expression:
		assert(store.expressionDelegate !is null);
		e = store.expressionDelegate(e.location);
		return;
	case Template:
		throw panic(i, "template used as a value.");
	case Type:
	case Alias:
	case Scope:
		throw panicUnhandled(i, i.value);
	}
}

bool replaceAAPostfixesIfNeeded(Context ctx, ir.Postfix postfix, ref ir.Exp exp)
{
	auto l = postfix.location;
	if (postfix.op == ir.Postfix.Op.Call) {
		assert(postfix.identifier is null);
		auto child = cast(ir.Postfix) postfix.child;
		if (child is null || child.identifier is null) {
			return false;
		}
		if (child.identifier.value != "get") {
			return false;
		}
		if (postfix.arguments.length != 2) {
			return false;
		}
		auto aa = cast(ir.AAType) realType(getExpType(ctx.lp, child.child, ctx.current));
		if (aa is null) {
			return false;
		}
		ir.ExpReference rtFn;
		auto args = new ir.Exp[](3);
		args[0] = copyExp(child.child);
		bool keyIsArray = isArray(realType(aa.key));
		bool valIsArray = isArray(realType(aa.value));
		if (keyIsArray && valIsArray) {
			rtFn = buildExpReference(l, ctx.lp.aaGetAA, ctx.lp.aaGetAA.name);
		} else if (!keyIsArray && valIsArray) {
			rtFn = buildExpReference(l, ctx.lp.aaGetPA, ctx.lp.aaGetPA.name);
		} else if (keyIsArray && !valIsArray) {
			rtFn = buildExpReference(l, ctx.lp.aaGetAP, ctx.lp.aaGetAP.name);
		} else {
			rtFn = buildExpReference(l, ctx.lp.aaGetPP, ctx.lp.aaGetPP.name);
		}
		if (keyIsArray) {
			args[1] = buildCastSmart(l, buildArrayType(l, buildVoid(l)), postfix.arguments[0]);
		} else {
			args[1] = buildCastSmart(l, buildUlong(l), postfix.arguments[0]);
		}
		if (valIsArray) {
			args[2] = buildCastSmart(l, buildArrayType(l, buildVoid(l)), postfix.arguments[1]);
		} else {
			args[2] = buildCastSmart(l, buildUlong(l), postfix.arguments[1]);
		}
		exp = buildCastSmart(l, aa.value, buildCall(l, rtFn, args));
		return true;
	}

	if (postfix.identifier is null) {
		return false;
	}
	auto aa = cast(ir.AAType) realType(getExpType(ctx.lp, postfix.child, ctx.current));
	if (aa is null) {
		return false;
	}
	ir.ExpReference rtFn;
	ir.Type type;
	ir.Exp[] arg = [copyExp(postfix.child)];
	switch (postfix.identifier.value) {
	case "keys":
		rtFn = buildExpReference(l, ctx.lp.aaGetKeys, ctx.lp.aaGetKeys.name);
		type = buildArrayType(l, aa.key);
		break;
	case "values":
		rtFn = buildExpReference(l, ctx.lp.aaGetValues, ctx.lp.aaGetValues.name);
		type = buildArrayType(l, aa.value);
		break;
	case "length":
		rtFn = buildExpReference(l, ctx.lp.aaGetLength, ctx.lp.aaGetLength.name);
		type = ctx.lp.settings.getSizeT(l);
		break;
	case "rehash":
		rtFn = buildExpReference(l, ctx.lp.aaRehash, ctx.lp.aaRehash.name);
		exp = buildCall(l, rtFn, arg);
		return true;
	default:
		return false;
	}
	assert(rtFn !is null);
	exp = buildDeref(l, buildCastSmart(l, buildPtrSmart(l, type), buildCall(l, rtFn, arg)));
	return true;
}

/**
 * Turns identifier postfixes into CreateDelegates, and resolves property function
 * calls in postfixes, type safe varargs, and explicit constructor calls.
 */
void extypeLeavePostfix(Context ctx, ref ir.Exp exp, ir.Postfix postfix)
{
	if (replaceAAPostfixesIfNeeded(ctx, postfix, exp)) {
		return;
	}
	ir.Postfix[] postfixes;
	ir.Postfix currentPostfix = postfix;
	do {
		postfixes ~= currentPostfix;
		currentPostfix = cast(ir.Postfix) currentPostfix.child;
	} while (currentPostfix !is null);

	// Given a.foo, if a is a pointer to a class, turn it into (*a).foo.
	auto lastType = getExpType(ctx.lp, postfixes[$-1].child, ctx.current);
	if (isPointerToClass(lastType)) {
		postfixes[$-1].child = buildDeref(postfixes[$-1].child.location, postfixes[$-1].child);
	}

	if (postfix.op != ir.Postfix.Op.Call) {
		auto type = getExpType(ctx.lp, postfix.child, ctx.current);
		/* If we end up with a identifier postfix that points
		 * at a struct, and retrieves a member function, then
		 * transform the op from Identifier to CreatePostfix.
		 */
		if (postfix.identifier !is null) {
			auto asStorage = cast(ir.StorageType) realType(type);
			if (asStorage !is null && canTransparentlyReferToBase(asStorage)) {
				type = asStorage.base;
			}

			auto tr = cast(ir.TypeReference) type;
			if (tr !is null) {
				type = tr.type;
			}

			if (type.nodeType != ir.NodeType.Struct &&
			    type.nodeType != ir.NodeType.Union &&
			    type.nodeType != ir.NodeType.Class) {
				return;
			}

			/// @todo this is probably an error.
			auto agg = cast(ir.Aggregate) type;
			ir.Scope[] scopes;
			auto aggScope = getScopeFromType(type);
			if (agg !is null ) foreach (aa; agg.anonymousAggregates) {
				scopes ~= aa.myScope;
			}
			ir.Variable aggVar;
			auto store = lookupAsThisScope(ctx.lp, aggScope, postfix.location, postfix.identifier.value);
			foreach (i, _scope; scopes) {
				auto tmpStore = lookupAsThisScope(ctx.lp, _scope, postfix.location, postfix.identifier.value);
				if (tmpStore is null) {
					continue;
				}
				if (store !is null) {
					throw makeAnonymousAggregateRedefines(agg.anonymousAggregates[i], postfix.identifier.value);
				}
				store = tmpStore;
				aggVar = agg.anonymousVars[i];
				// Keep checking to ensure anon aggs don't mask one another.
			}
			if (aggVar !is null) {
				assert(postfix.identifier !is null);
				auto origLookup = postfix.identifier.value;
				postfix.identifier.value = aggVar.name;
				exp = buildAccess(postfix.location, postfix, origLookup);
				return;
			}
			if (store is null) {
				throw makeNotMember(postfix, type, postfix.identifier.value);
			}

			if (store.kind != ir.Store.Kind.Function) {
				return;
			}

			assert(store.functions.length > 0, store.name);

			auto funcref = new ir.ExpReference();
			funcref.location = postfix.identifier.location;
			auto _ref = cast(ir.ExpReference) postfix.child;
			if (_ref !is null) funcref.idents = _ref.idents;
			funcref.idents ~= postfix.identifier.value;
			funcref.decl = buildSet(postfix.identifier.location, store.functions, funcref);
			ir.FunctionSet set = cast(ir.FunctionSet) funcref.decl;
			if (set !is null) assert(set.functions.length > 0);
			postfix.op = ir.Postfix.Op.CreateDelegate;
			postfix.memberFunction = funcref;
		}

		propertyToCallIfNeeded(postfix.location, ctx.lp, exp, ctx.current, postfixes);

		return;
	}

	auto type = getExpType(ctx.lp, postfix.child, ctx.current);
	bool thisCall;

	ir.CallableType asFunctionType;
	auto asFunctionSet = cast(ir.FunctionSetType) realType(type);
	ir.Function fn;

	auto eref = cast(ir.ExpReference) postfix.child;
	bool reeval = true;

	if (eref is null) {
		reeval = false;
		auto pchild = cast(ir.Postfix) postfix.child;
		if (pchild !is null) {
			eref = cast(ir.ExpReference) pchild.memberFunction;
		}
	}

	if (asFunctionSet !is null) {
		if (eref is null) {
			throw panic(postfix.location, "expected expref");
		}
		asFunctionSet.set.reference = eref;
		fn = selectFunction(ctx.lp, ctx.current, asFunctionSet.set, postfix.arguments, postfix.location);
		eref.decl = fn;
		asFunctionType = fn.type;

		if (reeval) {
			replaceExpReferenceIfNeeded(ctx, null, postfix.child, eref);
		}
	} else if (eref !is null) {
		fn = cast(ir.Function) eref.decl;
		asFunctionType = cast(ir.CallableType) realType(type);
		if (asFunctionType is null) {
			auto _storage = cast(ir.StorageType) type;
			if (_storage !is null) {
				asFunctionType = cast(ir.CallableType) _storage.base;
			}
			if (asFunctionType is null) {
				auto _class = cast(ir.Class) type;
				if (_class !is null) {
					// this(blah);
					fn = selectFunction(ctx.lp, ctx.current, _class.userConstructors, postfix.arguments, postfix.location);
					asFunctionType = fn.type;
					eref.decl = fn;
					thisCall = true;
				} else {
					throw makeBadCall(postfix, type);
				}
			}
		}
	}
	if (asFunctionType is null) {
		return;
	}

	// Not providing an argument to a homogenous variadic function.
	if (asFunctionType.homogenousVariadic && postfix.arguments.length + 1 == asFunctionType.params.length) {
		postfix.arguments ~= buildConstantNull(postfix.location, asFunctionType.params[$-1]);
	}

	// Hand check va_start(vl) and va_end(vl), then modify their calls.
	if (fn is ctx.lp.vaStartFunc || fn is ctx.lp.vaEndFunc || fn is ctx.lp.vaCStartFunc || fn is ctx.lp.vaCEndFunc) {
		if (postfix.arguments.length != 1) {
			throw makeWrongNumberOfArguments(postfix, postfix.arguments.length, 1);
		}
		auto etype = getExpType(ctx.lp, postfix.arguments[0], ctx.current);
		auto ptr = cast(ir.PointerType) etype;
		if (ptr is null || !isVoid(ptr.base)) {
			throw makeExpected(postfix, "va_list argument");
		}
		if (!isLValue(postfix.arguments[0])) {
			throw makeVaFooMustBeLValue(postfix.arguments[0].location, (fn is ctx.lp.vaStartFunc || fn is ctx.lp.vaCStartFunc) ? "va_start" : "va_end");
		}
		postfix.arguments[0] = buildAddrOf(postfix.arguments[0]);
		if (fn is ctx.lp.vaStartFunc) {
			assert(ctx.currentFunction.params[$-1].name == "_args");
			postfix.arguments ~= buildAccess(postfix.location, buildExpReference(postfix.location, ctx.currentFunction.params[$-1], "_args"), "ptr");
		}
		if (ctx.currentFunction.type.linkage == ir.Linkage.Volt) {
			if (fn is ctx.lp.vaStartFunc) {
				exp = buildVaArgStart(postfix.location, postfix.arguments[0], postfix.arguments[1]);
				return;
			} else if (fn is ctx.lp.vaEndFunc) {
				exp = buildVaArgEnd(postfix.location, postfix.arguments[0]);
				return;
			} else {
				throw makeExpected(postfix.location, "volt va_args function.");
			}
		}
	}

	if (asFunctionType.isScope && postfix.child.nodeType == ir.NodeType.Postfix) {
		auto asPostfix = cast(ir.Postfix) postfix.child;
		auto parentType = getExpType(ctx.lp, asPostfix.child, ctx.current);
		if (mutableIndirection(parentType)) {
			auto asStorageType = cast(ir.StorageType) realType(parentType);
			if (asStorageType is null || asStorageType.type != ir.StorageType.Kind.Scope) {
				throw makeBadCall(postfix, asFunctionType);
			}
		}
	}

	if (asFunctionType.hasVarArgs &&
	    asFunctionType.linkage == ir.Linkage.Volt) {
		ir.ExpReference asExp;
		if (postfix.child.nodeType == ir.NodeType.Postfix) {
			assert(postfix.op == ir.Postfix.Op.Call);
			auto pfix = cast(ir.Postfix) postfix.child;
			assert(pfix !is null);
			assert(pfix.op == ir.Postfix.Op.CreateDelegate);
			assert(pfix.memberFunction !is null);
			asExp = pfix.memberFunction;
		}
		if (asExp is null) {
			asExp = cast(ir.ExpReference) postfix.child;
		}
		auto asFunction = cast(ir.Function) asExp.decl;
		assert(asFunction !is null);

		auto callNumArgs = postfix.arguments.length;
		auto funcNumArgs = asFunctionType.params.length - 2; // 2 == the two hidden arguments
		if (callNumArgs < funcNumArgs) {
			throw makeWrongNumberOfArguments(postfix, callNumArgs, funcNumArgs);
		}
		auto amountOfVarArgs = callNumArgs - funcNumArgs;
		auto argsSlice = postfix.arguments[0 .. funcNumArgs];
		auto varArgsSlice = postfix.arguments[funcNumArgs .. $];

		auto tinfoClass = ctx.lp.typeInfoClass;
		auto tr = buildTypeReference(postfix.location, tinfoClass, tinfoClass.name);
		tr.location = postfix.location;
		auto array = new ir.ArrayType();
		array.location = postfix.location;
		array.base = tr;

		auto typeidsLiteral = new ir.ArrayLiteral();
		typeidsLiteral.location = postfix.location;
		typeidsLiteral.type = array;

		int[] sizes;
		int totalSize;
		ir.Type[] types;
		foreach (i, _exp; varArgsSlice) {
			auto etype = getExpType(ctx.lp, _exp, ctx.current);
			auto typeId = new ir.Typeid();
			typeId.location = postfix.location;
			typeId.type = copyTypeSmart(postfix.location, etype);
			typeidsLiteral.values ~= typeId;
			types ~= etype;
			sizes ~= size(postfix.location, ctx.lp, etype);
			totalSize += sizes[$-1];
		}

		postfix.arguments = argsSlice ~ typeidsLiteral ~ buildInternalArrayLiteralSliceSmart(postfix.location, buildArrayType(postfix.location, buildVoid(postfix.location)), types, sizes, totalSize, ctx.lp.memcpyFunc, varArgsSlice);
	}

	appendDefaultArguments(ctx, postfix.location, postfix.arguments, fn);
	if (!(asFunctionType.hasVarArgs || asFunctionType.params.length > 0 && asFunctionType.homogenousVariadic) &&
	    postfix.arguments.length != asFunctionType.params.length) {
		throw makeWrongNumberOfArguments(postfix, postfix.arguments.length, asFunctionType.params.length);
	}
	assert(asFunctionType.params.length <= postfix.arguments.length);
	foreach (i; 0 .. asFunctionType.params.length) {
		ir.StorageType.Kind stype;
		if (isRef(asFunctionType.params[i], stype)) { 
			if (!isLValue(postfix.arguments[i])) {
				throw makeNotLValue(postfix.arguments[i]);
			}
			if (stype == ir.StorageType.Kind.Ref && postfix.argumentTags[i] != ir.Postfix.TagKind.Ref) {
				throw makeNotTaggedRef(postfix.arguments[i]);
			}
			if (stype == ir.StorageType.Kind.Out && postfix.argumentTags[i] != ir.Postfix.TagKind.Out) {
				throw makeNotTaggedOut(postfix.arguments[i]);
			}
		}
		if (asFunctionType.homogenousVariadic && i == asFunctionType.params.length - 1) {
			auto etype = getExpType(ctx.lp, postfix.arguments[i], ctx.current);
			auto arr = cast(ir.ArrayType) asFunctionType.params[i];
			if (arr is null) {
				throw panic(postfix.location, "homogenous variadic not array type");
			}
			if (!typesEqual(etype, arr)) {
				auto exps = postfix.arguments[i .. $];
				foreach (ref aexp; exps) {
					extypePass(ctx, aexp, arr.base);
				}
				postfix.arguments[i] = buildInternalArrayLiteralSmart(exps[0].location, asFunctionType.params[i], exps);
				postfix.arguments.length = i + 1;
				break;
			}
		}
		extypePass(ctx, postfix.arguments[i], asFunctionType.params[i]);
	}

	if (thisCall) {
		// Explicit constructor call.
		auto tvar = getThisVar(postfix.location, ctx.lp, ctx.current);
		auto tref = buildExpReference(postfix.location, tvar, "this");
		postfix.arguments ~= buildCastToVoidPtr(postfix.location, tref);
	}
}

/**
 * This function acts as a extyperExpReference function would do,
 * but it also takes a extra type context which is used for the
 * cases when looking up Member variables via Types.
 *
 * pkg.mod.Class.member = 4;
 *
 * Even though FunctionSets might need rewriting they are not rewritten
 * directly but instead this function is called after they have been
 * rewritten and the ExpReference has been resolved to a single Function.
 */
bool replaceExpReferenceIfNeeded(Context ctx,
                                 ir.Type referredType, ref ir.Exp exp, ir.ExpReference eRef)
{
	// Hold onto your hats because this is ugly!
	// But this needs to be run after this function has early out
	// or rewritten the lookup.
	scope (success) {
		propertyToCallIfNeeded(exp.location, ctx.lp, exp, ctx.current, null);
	}

	// For vtable and property.
	if (eRef.rawReference) {
		return false;
	}
	
	// Early out on static vars.
	// Or function sets.
	auto decl = eRef.decl;
	final switch (decl.declKind) with (ir.Declaration.Kind) {
	case Function:
		auto asFn = cast(ir.Function)decl;
		if (isFunctionStatic(asFn)) {
			return false;
		}
		break;
	case Variable:
		auto asVar = cast(ir.Variable)decl;
		if (isVariableStatic(asVar)) {
			return false;
		}
		break;
	case FunctionParam:
		return false;
	case EnumDeclaration:
	case FunctionSet:
		return false;
	}

	ir.Exp nestedLookup;
	auto ffn = getParentFunction(ctx.current);
	if (ffn.nestStruct !is null) {
		auto access = buildAccess(eRef.location, buildExpReference(eRef.location, ffn.nestedVariable), "this");
		nestedLookup = buildAccess(eRef.location, access, eRef.idents[$-1]);
	}
	auto thisVar = getThisVar(eRef.location, ctx.lp, ctx.current);
	assert(thisVar !is null);

	auto tr = cast(ir.TypeReference) thisVar.type;
	if (tr is null) {
		throw panic(eRef, "not TypeReference thisVar");
	}

	auto thisAgg = cast(ir.Aggregate) tr.type;
	if (thisAgg is null) {
		throw panic(eRef, "thisVar not aggregate");
	}

	/// Use this for if type not provided.
	if (referredType is null) {
		referredType = thisAgg;
	}

	auto expressionAgg = cast(ir.Aggregate) referredType;
	if (expressionAgg is null) {
		throw panic(eRef, "referredType not Aggregate");
	}

	string ident = eRef.idents[$-1];
	auto store = lookupOnlyThisScope(ctx.lp, expressionAgg.myScope, exp.location, ident);
	if (store !is null && store.node !is eRef.decl) {
		if (eRef.decl.nodeType !is ir.NodeType.FunctionParam) {
			bool found = false;
			foreach (fn; store.functions) {
				if (fn is eRef.decl) {
					found = true;
				}
			}
			if (!found) {
				throw makeNotMember(eRef, expressionAgg, ident);
			}
		}
	}

	auto thisClass = cast(ir.Class) thisAgg;
	auto expressionClass = cast(ir.Class) expressionAgg;
	if (thisClass !is null && expressionClass !is null) {
		if (!thisClass.isOrInheritsFrom(expressionClass)) {
			throw makeInvalidType(exp, expressionClass);
		}
	} else if (thisAgg !is expressionAgg) {
		throw makeInvalidThis(eRef, thisAgg, expressionAgg, ident);
	}

	ir.Exp thisRef = buildExpReference(eRef.location, thisVar, "this");
	if (thisClass !is expressionClass) {
		thisRef = buildCastSmart(eRef.location, expressionClass, thisRef);
	}

	if (eRef.decl.declKind == ir.Declaration.Kind.Function) {
		exp = buildCreateDelegate(eRef.location, thisRef, eRef);
	} else {
		if (nestedLookup !is null) {
			exp = nestedLookup; 
		} else {
			exp = buildAccess(eRef.location, thisRef, ident);
		}
	}

	return true;
}

/// Rewrite foo.prop = 3 into foo.prop(3).
void rewritePropertyFunctionAssign(Context ctx, ref ir.Exp e, ir.BinOp bin)
{
	if (bin.op != ir.BinOp.Op.Assign) {
		return;
	}
	auto asExpRef = cast(ir.ExpReference) bin.left;
	ir.Postfix asPostfix;
	string functionName;

	// Not a stand alone function, check if it's a member function.
	if (asExpRef is null) {
		asPostfix = cast(ir.Postfix) bin.left;
		if (asPostfix is null) {
			return;
		}
		if (asPostfix.op == ir.Postfix.Op.CreateDelegate) {
			asExpRef = asPostfix.memberFunction;
		} else if (asPostfix.op == ir.Postfix.Op.Identifier) {
			asExpRef = cast(ir.ExpReference) asPostfix.child;
			assert(asPostfix.identifier !is null);
			functionName = asPostfix.identifier.value;
		}
		if (asExpRef is null) {
			return;
		}
	}

	auto asFunction = cast(ir.Function) asExpRef.decl;
	// Classes aren't filled in yet, so try to see if it's one of those.
	if (asFunction is null) {
		auto asVariable = cast(ir.Variable) asExpRef.decl;
		if (asVariable is null) {
			return;
		}
		auto asTR = cast(ir.TypeReference) asVariable.type;
		if (asTR is null) {
			return;
		}
		auto asClass = cast(ir.Class) asTR.type;
		if (asClass is null) {
			return;
		}
		auto functionStore = lookupOnlyThisScope(ctx.lp, asClass.myScope, bin.location, functionName);
		if (functionStore is null) {
			return;
		}
		if (functionStore.functions.length != 1) {
			assert(functionStore.functions.length == 0);
			return;
		}
		asFunction = functionStore.functions[0];
		assert(asFunction !is null);
	}


	if (!asFunction.type.isProperty) {
		return;
	}
	if (asFunction.type.params.length != 1) {
		return;
	}
	auto call = buildCall(bin.location, asFunction, [bin.right], asFunction.name);
	assert(call.arguments.length == 1);
	assert(call.arguments[0] !is null);
	
	if (asPostfix !is null) {
		call.child = asPostfix;
	}
	e = call;
	return;
}

/**
 * Handles <type>.<identifier>, like 'int.min' and the like.
 */
void extypeTypeLookup(Context ctx, ref ir.Exp exp, ir.Postfix[] postfixIdents, ir.Type type)
{
	if (postfixIdents.length != 1) {
		throw makeExpected(type, "max or min");
	}
	if (postfixIdents[0].identifier.value != "max" && postfixIdents[0].identifier.value != "min") {
		throw makeExpected(type, "max or min");
	}
	bool max = postfixIdents[0].identifier.value == "max";

	auto pointer = cast(ir.PointerType) realType(type);
	if (pointer !is null) {
		if (ctx.lp.settings.isVersionSet("V_LP64")) {
			exp = buildConstantInt(type.location, max ? 8 : 0);
		} else {
			exp = buildConstantInt(type.location, max ? 4 : 0);
		}
		return;
	}

	auto prim = cast(ir.PrimitiveType) realType(type);
	if (prim is null) {
		throw makeExpected(type, "primitive type");
	}

	final switch (prim.type) with (ir.PrimitiveType.Kind) {
	case Bool:
		exp = buildConstantInt(prim.location, max ? 1 : 0);
		break;
	case Ubyte, Char:
		exp = buildConstantInt(prim.location, max ? 255 : 0);
		break;
	case Byte:
		exp = buildConstantInt(prim.location, max ? 127 : -128);
		break;
	case Ushort, Wchar:
		exp = buildConstantInt(prim.location, max ? 65535 : 0);
		break;
	case Short:
		exp = buildConstantInt(prim.location, max? 32767 : -32768);
		break;
	case Uint, Dchar:
		exp = buildConstantUint(prim.location, max ? 4294967295U : 0);
		break;
	case Int:
		exp = buildConstantInt(prim.location, max ? 2147483647 : -2147483648);
		break;
	case Ulong:
		exp = buildConstantUlong(prim.location, max ? 18446744073709551615UL : 0);
		break;
	case Long:
		/* We use a ulong here because -9223372036854775808 is not converted as a string
		 * with a - on the front, but just the number 9223372036854775808 that is in a
		 * Unary minus expression. And because it's one more than will fit in a long, we
		 * have to use the next size up.
		 */
		exp = buildConstantUlong(prim.location, max ? 9223372036854775807UL : -9223372036854775808UL);
		break;
	case Float, Double, Real, Void:
		throw makeExpected(prim, "integral type");
	}
}

/**
 * Turn identifier postfixes into <ExpReference>.ident.
 */
void extypePostfixIdentifier(Context ctx, ref ir.Exp exp, ir.Postfix postfix)
{
	if (postfix.op != ir.Postfix.Op.Identifier)
		return;

	ir.Postfix[] postfixIdents; // In reverse order.
	ir.IdentifierExp identExp; // The top of the stack.
	ir.IdentifierExp firstExp;
	ir.Postfix currentP = postfix;

	while (true) {
		if (currentP.identifier is null)
			throw panic(currentP, "null identifier.");

		postfixIdents = [currentP] ~ postfixIdents;

		if (currentP.child.nodeType == ir.NodeType.Postfix) {
			auto child = cast(ir.Postfix) currentP.child;

			// for things like func().structVar;
			if (child.op != ir.Postfix.Op.Identifier) {
				return;
			}

			currentP = child;

		} else if (currentP.child.nodeType == ir.NodeType.IdentifierExp) {
			identExp = cast(ir.IdentifierExp) currentP.child;
			if (firstExp is null) {
				firstExp = identExp;
				assert(firstExp !is null);
			}
			break;
		} else if (currentP.child.nodeType == ir.NodeType.TypeExp) {
			auto typeExp = cast(ir.TypeExp) currentP.child;
			extypeTypeLookup(ctx, exp, postfixIdents, typeExp.type);
			return;
		} else {
			// For instance typeid(int).mangledName.
			return;
		}
	}

	ir.ExpReference _ref;
	ir.Location loc;
	string ident;
	string[] idents;

	/// Fillout _ref with data from ident.
	void filloutReference(ir.Store store)
	{
		_ref = new ir.ExpReference();
		_ref.location = loc;
		_ref.idents = idents;

		assert(store !is null);
		if (store.kind == ir.Store.Kind.Value) {
			auto var = cast(ir.Variable) store.node;
			tagNestedVariables(ctx, var, store, postfix.child);
			assert(var !is null);
			_ref.decl = var;
		} else if (store.kind == ir.Store.Kind.Function) {
			assert(store.functions.length == 1);
			auto fn = store.functions[0];
			_ref.decl = fn;
		} else if (store.kind == ir.Store.Kind.FunctionParam) {
			auto fp = cast(ir.FunctionParam) store.node;
			assert(fp !is null);
			_ref.decl = fp;
		} else {
			throw panicUnhandled(_ref, to!string(store.kind));
		}

		// Sanity check.
		if (_ref.decl is null) {
			throw panic(_ref, "empty ExpReference declaration.");
		}
	}

	/**
	 * Our job here is to work trough the stack of postfixs and
	 * the top identifier exp looking for the first variable or
	 * function.
	 *
	 * pkg.mod.Class.Child.'staticVar'.field.anotherField;
	 *
	 * Would have 6 postfixs and IdentifierExp == "pkg".
	 * We would skip 3 postfixes and the IdentifierExp.
	 * Postfix "anotherField" ->
	 *   Postfix "field" ->
	 *     ExpReference "pkg.mod.Class.Child.staticVar".
	 *
	 *
	 * pkg.mod.'staticVar'.field;
	 *
	 * Would have 2 Postfixs and the IdentifierExp.
	 * We would should skip everything but one Postfix.
	 * Postfix "field" ->
	 *   ExpReference "pkg.mod.staticVar".
	 */

	ir.Scope _scope;
	ir.Store store;
	ir.Type lastType;

	// First do the identExp lookup.
	// postfix is in an unknown context at this point.
	{
		_scope = ctx.current;
		loc = identExp.location;
		ident = identExp.value;
		idents = [ident];

		/// @todo handle leading dot.
		assert(!identExp.globalLookup);

		ir.Exp withResult;
		foreach (withStatement; _scope.withStatements) {
			auto withExp = withStatement.exp;
			withResult = withLookup(ctx, withExp, ctx.current, ident);
			if (withResult !is null) {
				postfixIdents[0].child = withResult;
				return extypePostfixIdentifier(ctx, exp, postfix);
			}
		}
		store = lookup(ctx.lp, _scope, loc, ident);
	}

	// Now do the looping.
	do {
		if (store is null) {
			// @todo keep track of what the context was that we looked into.
			throw makeFailedLookup(loc, ident);
		}

		lastType = null;
		final switch(store.kind) with (ir.Store.Kind) {
		case Type:
			lastType = cast(ir.Type) store.node;
			assert(lastType !is null);
			auto prim = cast(ir.PrimitiveType) lastType;
			if (prim !is null) {
				extypeTypeLookup(ctx, exp, postfixIdents, prim);
				return;
			}
			goto case Scope;
		case Scope:
			_scope = getScopeFromStore(store);
			if (_scope is null)
				throw panic(postfix, "missing scope");

			if (postfixIdents.length == 0)
				throw makeInvalidUseOfStore(postfix, store);

			postfix = postfixIdents[0];
			postfixIdents = postfixIdents[1 .. $];
			ident = postfix.identifier.value;
			loc = postfix.identifier.location;

			store = lookupAsImportScope(ctx.lp, _scope, loc, ident);
			idents = [ident] ~ idents;

			break;
		case EnumDeclaration:
			auto ed = cast(ir.EnumDeclaration)store.node;

			// If we want aggregate enums this needs to be fixed.
			assert(postfixIdents.length == 0);

			exp = copyExp(ed.assign);
			return;
		case Value:
		case Function:
		case FunctionParam:
			filloutReference(store);
			break;
		case Template:
		case Expression:
			throw makeInvalidUseOfStore(postfix, store);
		case Alias:
			throw panic(postfix, "alias scope");
		}

	} while(_ref is null);

	assert(_ref !is null);


	// We are retriving a Variable or Function directly.
	if (postfixIdents.length == 0) {
		exp = _ref;
		replaceExpReferenceIfNeeded(ctx, lastType, exp, _ref);
	} else {
		postfix = postfixIdents[0];
		postfix.child = _ref;
		replaceExpReferenceIfNeeded(ctx, lastType, postfix.child, _ref);
	}
}

void extypePostfixIndex(Context ctx, ref ir.Exp exp, ir.Postfix postfix)
{
	if (postfix.op != ir.Postfix.Op.Index)
		return;

	auto type = getExpType(ctx.lp, postfix.child, ctx.current);
	if (type.nodeType == ir.NodeType.AAType) {
		auto aa = cast(ir.AAType)type;
		extypeAssign(ctx, postfix.arguments[0], aa.key);
	}
}

void extypePostfix(Context ctx, ref ir.Exp exp, ir.Postfix postfix)
{
	if (opOverloadRewriteIndex(ctx, postfix, exp)) {
		return;
	}
	rewriteSuperIfNeeded(exp, postfix, ctx.current, ctx.lp);
	extypePostfixIdentifier(ctx, exp, postfix);
	extypePostfixIndex(ctx, exp, postfix);
}

/**
 * Stops casting to an overloaded function name, casting from null, and wires
 * up some runtime magic needed for classes.
 */
void handleCastTo(Context ctx, ref ir.Exp exp, ir.Unary unary)
{
	assert(unary.type !is null);
	assert(unary.value !is null);

	auto type = realType(getExpType(ctx.lp, unary.value, ctx.current));
	if (type.nodeType == ir.NodeType.FunctionSetType) {
		auto fset = cast(ir.FunctionSetType) type;
		throw makeCannotDisambiguate(unary, fset.set.functions);
	}

	// Handling cast(Foo)null
	if (handleNull(unary.type, unary.value, type) !is null) {
		exp = unary.value;
		return;
	}

	auto to = getClass(unary.type);
	auto from = getClass(type);

	if (to is null || from is null || to is from) {
		return;
	}

	auto fn = retrieveFunctionFromObject(ctx.lp, unary.location, "vrt_handle_cast");
	assert(fn !is null);

	auto fnref = buildExpReference(unary.location, fn, "vrt_handle_cast");
	auto tid = buildTypeidSmart(unary.location, to);
	auto val = buildCastToVoidPtr(unary.location, unary.value);
	unary.value = buildCall(unary.location, fnref, [val, cast(ir.Exp)tid]);
}

/**
 * Type new expressions.
 */
void handleNew(Context ctx, ref ir.Exp exp, ir.Unary _unary)
{
	assert(_unary.type !is null);

	if (!_unary.hasArgumentList) {
		return;
	}
	auto tr = cast(ir.TypeReference) _unary.type;
	if (tr is null) {
		return;
	}
	auto _struct = cast(ir.Struct) tr.type;
	if (_struct !is null) {
		assert(_unary.hasArgumentList);
		throw makeStructConstructorsUnsupported(_unary);
	}
	auto _class = cast(ir.Class) tr.type;
	if (_class is null) {
		return;
	}

	if (_class.isAbstract) {
		throw makeNewAbstract(_unary, _class);
	}

	// Needed because of userConstructors.
	ctx.lp.actualize(_class);

	auto fn = selectFunction(ctx.lp, ctx.current, _class.userConstructors, _unary.argumentList, _unary.location);
	appendDefaultArguments(ctx, _unary.location, _unary.argumentList, fn);

	ctx.lp.resolve(ctx.current, fn);

	for (size_t i = 0; i < _unary.argumentList.length; ++i) {
		extypeAssign(ctx, _unary.argumentList[i], fn.type.params[i]);
	}
}

void extypeUnary(Context ctx, ref ir.Exp exp, ir.Unary _unary)
{
	switch (_unary.op) with (ir.Unary.Op) {
	case Cast:
		return handleCastTo(ctx, exp, _unary);
	case New:
		return handleNew(ctx, exp, _unary);
	default:
	}
}

/**
 * Everyone's favourite: integer promotion! :D!
 * In general, converts to the largest type needed in a binary expression.
 */
void extypeBinOp(Context ctx, ir.BinOp bin, ir.PrimitiveType lprim, ir.PrimitiveType rprim)
{
	auto leftsz = size(lprim.type);
	auto rightsz = size(rprim.type);

	if (bin.op != ir.BinOp.Op.Assign &&
	    bin.op != ir.BinOp.Op.Is &&
	    bin.op != ir.BinOp.Op.NotIs &&
	    bin.op != ir.BinOp.Op.Equal &&
	    bin.op != ir.BinOp.Op.NotEqual) {
		if (isBool(lprim)) {
			auto i = new ir.PrimitiveType(ir.PrimitiveType.Kind.Int);
			lprim = i;
			bin.left = buildCastSmart(i, bin.left);
		}
		if (isBool(rprim)) {
			auto i = new ir.PrimitiveType(ir.PrimitiveType.Kind.Int);
			rprim = i;
			bin.right = buildCastSmart(i, bin.right);
		}
	}

	if (isIntegral(lprim) && isIntegral(rprim)) {
		bool leftUnsigned = isUnsigned(lprim.type);
		bool rightUnsigned = isUnsigned(rprim.type);
		if (leftUnsigned != rightUnsigned) {
			if (leftUnsigned) {
				if (fitsInPrimitive(lprim, bin.right)) {
					bin.right = buildCastSmart(lprim, bin.right);
					rightUnsigned = true;
					rightsz = leftsz;
				}
			} else {
				if (fitsInPrimitive(rprim, bin.left)) {
					bin.left = buildCastSmart(rprim, bin.left);
					leftUnsigned = true;
					leftsz = rightsz;
				}
			}
			if (leftUnsigned != rightUnsigned) {
				throw makeTypeIsNot(bin, rprim, lprim);
			}
		}
	}


	auto intsz = size(ir.PrimitiveType.Kind.Int);
	int largestsz;
	ir.Type largestType;

	if ((isFloatingPoint(lprim) && isFloatingPoint(rprim)) || (isIntegral(lprim) && isIntegral(rprim))) {
		if (leftsz > rightsz) {
			largestsz = leftsz;
			largestType = lprim;
		} else {
			largestsz = rightsz;
			largestType = rprim;
		}

		if (bin.op != ir.BinOp.Op.Assign && intsz > largestsz && isIntegral(lprim)) {
			largestsz = intsz;
			largestType = new ir.PrimitiveType(ir.PrimitiveType.Kind.Int);
		}

		if (leftsz < largestsz) {
			bin.left = buildCastSmart(largestType, bin.left);
		}

		if (rightsz < largestsz) {
			bin.right = buildCastSmart(largestType, bin.right);
		}

		return;
	}

	if (isFloatingPoint(lprim) && isIntegral(rprim)) {
		bin.right = buildCastSmart(lprim, bin.right);
	} else {
		bin.left = buildCastSmart(rprim, bin.left);
	}
}

bool opOverloadRewrite(Context ctx, ir.BinOp binop, ref ir.Exp exp)
{
	auto l = exp.location;
	auto _agg = opOverloadableOrNull(getExpType(ctx.lp, binop.left, ctx.current));
	if (_agg is null) {
		return false;
	}
	string overfn = overloadName(binop.op);
	if (overfn.length == 0) {
		return false;
	}
	auto store = lookupOnlyThisScope(ctx.lp, _agg.myScope, l, overfn);
	if (store is null || store.functions.length == 0) {
		throw makeAggregateDoesNotDefineOverload(exp.location, _agg, overfn);
	}
	auto fn = selectFunction(ctx.lp, ctx.current, store.functions, [binop.right], l);
	assert(fn !is null);
	exp = buildCall(l, buildCreateDelegate(l, binop.left, buildExpReference(l, fn, overfn)), [binop.right]);
	return true;
}

bool opOverloadRewriteIndex(Context ctx, ir.Postfix pfix, ref ir.Exp exp)
{
	if (pfix.op != ir.Postfix.Op.Index) {
		return false;
	}
	auto type = getExpType(ctx.lp, pfix.child, ctx.current);
	auto _agg = opOverloadableOrNull(type);
	if (_agg is null) {
		return false;
	}
	auto name = overloadIndexName();
	auto store = lookupOnlyThisScope(ctx.lp, _agg.myScope, exp.location, name);
	if (store is null || store.functions.length == 0) {
		throw makeAggregateDoesNotDefineOverload(exp.location, _agg, name);
	}
	assert(pfix.arguments.length > 0 && pfix.arguments[0] !is null);
	auto fn = selectFunction(ctx.lp, ctx.current, store.functions, [pfix.arguments[0]], exp.location);
	assert(fn !is null);
	exp = buildCall(exp.location, buildCreateDelegate(exp.location, pfix.child, buildExpReference(exp.location, fn, name)), [pfix.arguments[0]]);
	return true;
}

/**
 * Handles logical operators (making a && b result in a bool),
 * binary of storage types, otherwise forwards to assign or primitive
 * specific functions.
 */
void extypeBinOp(Context ctx, ir.BinOp binop, ref ir.Exp exp)
{
	auto ltype = realType(getExpType(ctx.lp, binop.left, ctx.current));
	auto rtype = realType(getExpType(ctx.lp, binop.right, ctx.current));

	if (handleIfNull(ctx, rtype, binop.left)) return;
	if (handleIfNull(ctx, ltype, binop.right)) return;

	if (opOverloadRewrite(ctx, binop, exp)) {
		return;
	}

	// key in aa => some_vrt_call(aa, key)
	if (binop.op == ir.BinOp.Op.In) {
		auto asAA = cast(ir.AAType) rtype;
		if (asAA is null) {
			throw makeExpected(binop.right.location, "associative array");
		}
		extypeAssign(ctx, binop.left, asAA.key);
		ir.Exp rtFn, key;
		auto l = binop.location;
		if (isArray(ltype)) {
			rtFn = buildExpReference(l, ctx.lp.aaInArray, ctx.lp.aaInArray.name);
			key = buildCast(l, buildArrayType(l, buildVoid(l)), copyExp(binop.left));
		} else {
			rtFn = buildExpReference(l, ctx.lp.aaInPrimitive, ctx.lp.aaInPrimitive.name);
			key = buildCast(l, buildUlong(l), copyExp(binop.left));
		}
		assert(rtFn !is null);
		assert(key !is null);

		auto args = new ir.Exp[](2);
		args[0] = copyExp(binop.right);
		args[1] = key;

		auto retptr = buildPtrSmart(l, asAA.value);
		auto call = buildCall(l, rtFn, args);
		exp = buildCast(l, retptr, call);
		return;
	}

	switch(binop.op) with(ir.BinOp.Op) {
	case AddAssign, SubAssign, MulAssign, DivAssign, ModAssign, AndAssign,
	     OrAssign, XorAssign, CatAssign, LSAssign, SRSAssign, RSAssign, PowAssign, Assign:
		// TODO this needs to be changed if there is operator overloading
		auto asPostfix = cast(ir.Postfix)binop.left;
		if (asPostfix !is null) {
			auto postfixLeft = getExpType(ctx.lp, asPostfix.child, ctx.current);
			if (postfixLeft !is null &&
			    postfixLeft.nodeType == ir.NodeType.AAType &&
			    asPostfix.op == ir.Postfix.Op.Index) {
				auto aa = cast(ir.AAType)postfixLeft;

				extypeAssign(ctx, binop.right, aa.value);
			}
		}
		break;
	default: break;
	}


	if (binop.op == ir.BinOp.Op.Assign) {
		if (effectivelyConst(ltype)) {
			throw makeCannotModify(binop, ltype);
		}

		extypeAssign(ctx, binop.right, ltype);

		return;
	}

	if (binop.op == ir.BinOp.Op.AndAnd || binop.op == ir.BinOp.Op.OrOr) {
		auto boolType = new ir.PrimitiveType(ir.PrimitiveType.Kind.Bool);
		if (!typesEqual(ltype, boolType)) {
			binop.left = buildCastSmart(boolType, binop.left);
		}
		if (!typesEqual(rtype, boolType)) {
			binop.right = buildCastSmart(boolType, binop.right);
		}
		return;
	}

	if ((binop.op == ir.BinOp.Op.Cat || binop.op == ir.BinOp.Op.CatAssign) &&
	    ltype.nodeType == ir.NodeType.ArrayType) {
		if (binop.op == ir.BinOp.Op.CatAssign && effectivelyConst(ltype)) {
			throw makeCannotModify(binop, ltype);
		}
		extypeCat(ctx, binop, cast(ir.ArrayType)ltype, rtype);
		return;
	}

	if (ltype.nodeType == ir.NodeType.PrimitiveType && rtype.nodeType == ir.NodeType.PrimitiveType) {
		auto lprim = cast(ir.PrimitiveType) ltype;
		auto rprim = cast(ir.PrimitiveType) rtype;
		assert(lprim !is null && rprim !is null);
		extypeBinOp(ctx, binop, lprim, rprim);
	}

	if (ltype.nodeType == ir.NodeType.StorageType || rtype.nodeType == ir.NodeType.StorageType) {
		if (ltype.nodeType == ir.NodeType.StorageType) {
			binop.left = buildCastSmart(rtype, binop.left);
		} else {
			binop.right = buildCastSmart(ltype, binop.right);
		}
	}
}

/**
 * Ensure concatentation is sound.
 */
void extypeCat(Context ctx, ir.BinOp bin, ir.ArrayType left, ir.Type right)
{
	if (typesEqual(left, right) ||
	    typesEqual(right, left.base)) {
		return;
	}

	auto rarray = cast(ir.ArrayType) realType(right);
	if (rarray !is null && isImplicitlyConvertable(rarray.base, left.base) && (isConst(left.base) || isImmutable(left.base))) {
		return;
	}

	extypeAssign(ctx, bin.right, rarray is null ? left.base : left);
	bin.right = buildCastSmart(left.base, bin.right);
}

void extypeTernary(Context ctx, ir.Ternary ternary)
{
	auto baseType = getExpType(ctx.lp, ternary.ifTrue, ctx.current);
	extypeAssign(ctx, ternary.ifFalse, baseType);

	auto condType = getExpType(ctx.lp, ternary.condition, ctx.current);
	if (!isBool(condType)) {
		ternary.condition = buildCastToBool(ternary.condition.location, ternary.condition);
	}
}

/// Replace TypeOf with its expression's type, if needed.
void replaceTypeOfIfNeeded(Context ctx, ref ir.Type type)
{
	auto asTypeOf = cast(ir.TypeOf) realType(type);
	if (asTypeOf is null) {
		assert(type.nodeType != ir.NodeType.TypeOf);
		return;
	}

	type = copyTypeSmart(asTypeOf.location, getExpType(ctx.lp, asTypeOf.exp, ctx.current));
}

/**
 * Ensure that a thrown type inherits from Throwable.
 */
void extypeThrow(Context ctx, ir.ThrowStatement t)
{
	auto throwable = cast(ir.Class) retrieveTypeFromObject(ctx.lp, t.location, "Throwable");
	assert(throwable !is null);

	auto type = getExpType(ctx.lp, t.exp, ctx.current);
	auto asClass = cast(ir.Class) type;
	if (asClass is null) {
		throw makeThrowOnlyThrowable(t.exp, type);
	}

	if (!asClass.isOrInheritsFrom(throwable)) {
		throw makeThrowNoInherits(t.exp, asClass);
	}

	if (asClass !is throwable) {
		t.exp = buildCastSmart(t.exp.location, throwable, t.exp);
	}
}

/**
 * Correct this references in nested functions.
 */
void handleNestedThis(ir.Function fn)
{
	auto np = fn.nestedVariable;
	auto ns = fn.nestStruct;
	if (np is null || ns is null) {
		return;
	}
	size_t index;
	for (index = 0; index < fn._body.statements.length; ++index) {
		if (fn._body.statements[index] is np) {
			break;
		}
	}
	if (++index >= fn._body.statements.length) {
		return;
	}
	if (fn.thisHiddenParameter !is null) {
		auto l = buildAccess(fn.location, buildExpReference(np.location, np, np.name), "this");
		auto tv = fn.thisHiddenParameter;
		auto r = buildExpReference(fn.location, tv, tv.name);
		r.doNotRewriteAsNestedLookup = true;
		ir.Node n = buildExpStat(l.location, buildAssign(l.location, l, r));
		fn._body.statements.insertInPlace(index++, n);
	}
}

/**
 * Given a nested function fn, add its parameters to the nested
 * struct and insert statements after the nested declaration.
 */
void handleNestedParams(Context ctx, ir.Function fn)
{
	auto np = fn.nestedVariable;
	auto ns = fn.nestStruct;
	if (np is null || ns is null) {
		return;
	}

	// This is needed for the parent function.
	size_t index;
	for (index = 0; index < fn._body.statements.length; ++index) {
		if (fn._body.statements[index] is np) {
			break;
		}
	}
	++index;

	foreach (param; fn.params) {
		if (!param.hasBeenNested) {
			param.hasBeenNested = true;
			ensureResolved(ctx.lp, ctx.current, param.type);
			auto var = buildVariableSmart(param.location, param.type, ir.Variable.Storage.Field, param.name);
			addVarToStructSmart(ns, var);

			// Insert an assignment of the param to the nest struct.
			auto l = buildAccess(param.location, buildExpReference(np.location, np, np.name), param.name);
			auto r = buildExpReference(param.location, param, param.name);
			r.doNotRewriteAsNestedLookup = true;
			ir.Node n = buildExpStat(l.location, buildAssign(l.location, l, r));
			if (fn.nestedHiddenParameter !is null) {
				// Nested function.
				fn._body.statements = n ~ fn._body.statements;
			} else {
				// Parent function with nested children.
				fn._body.statements.insertInPlace(index++, n);
			}
		}
	}
}


struct ArrayCase
{
	ir.Exp originalExp;
	ir.SwitchCase _case;
	ir.IfStatement lastIf;
}

/**
 * Ensure that a given switch statement is semantically sound.
 * Errors on bad final switches (doesn't cover all enum members, not on an enum at all),
 * and checks for doubled up cases.
 */
void verifySwitchStatement(Context ctx, ir.SwitchStatement ss)
{
	auto hashFunction = retrieveFunctionFromObject(ctx.lp, ss.location, "vrt_hash");

	auto conditionType = realType(getExpType(ctx.lp, ss.condition, ctx.current), false, true);
	auto originalCondition = ss.condition;
	if (isArray(conditionType)) {
		auto l = ss.location;
		auto asArray = cast(ir.ArrayType) conditionType;
		assert(asArray !is null);
		ir.Exp ptr = buildCastSmart(buildVoidPtr(l), buildAccess(l, copyExp(ss.condition), "ptr"));
		ir.Exp length = buildBinOp(l, ir.BinOp.Op.Mul, buildAccess(l, copyExp(ss.condition), "length"),
				buildAccess(l, buildTypeidSmart(l, asArray.base), "size"));
		ss.condition = buildCall(ss.condition.location, hashFunction, [ptr, length]);
		conditionType = buildUint(ss.condition.location);
	}

	ArrayCase[uint] arrayCases;
	size_t[] toRemove;  // Indices of cases that have been folded into a collision case.

	foreach (i, _case; ss.cases) {
		void replaceWithHashIfNeeded(ref ir.Exp exp) 
		{
			if (exp !is null) {
				// If the case needs to be rewritten via the switch's with(s), it's done here.
				int replaced;
				foreach (wexp; ss.withs) {
					auto etype = getExpType(ctx.lp, wexp, ctx.current);
					auto iexp = cast(ir.IdentifierExp) exp;
					if (iexp is null) {
						continue;
					}
					auto access = buildAccess(_case.location, wexp, iexp.value);
					ir.Class dummyClass;
					string dummyString;
					ir.Scope tmpScope;
					retrieveScope(ctx.lp, etype, access, tmpScope, dummyClass, dummyString);
					if (tmpScope is null) {
						continue;
					}
					auto store = lookupOnlyThisScope(ctx.lp, tmpScope, _case.location, iexp.value);
					if (store is null) {
						continue;
					}
					auto decl = cast(ir.Declaration) store.node;
					if (decl is null) {
						continue;
					}
					exp = buildExpReference(_case.location, decl, iexp.value);
					replaced++;
				}
				if (replaced >= 2) {
					throw makeWithCreatesAmbiguity(_case.location);
				}
				// Back to replacing cases with hashes if needed.
				auto etype = getExpType(ctx.lp, exp, ctx.current);
				if (isArray(etype)) {
					uint h;
					auto constant = cast(ir.Constant) exp;
					if (constant !is null) {
						assert(isString(etype));
						assert(constant._string[0] == '\"');
						assert(constant._string[$-1] == '\"');
						auto str = constant._string[1..$-1];
						h = hash(cast(void*) str.ptr, str.length * str[0].sizeof);
					} else {
						auto alit = cast(ir.ArrayLiteral) exp;
						assert(alit !is null);
						auto atype = cast(ir.ArrayType) etype;
						assert(atype !is null);
						uint[] intArrayData;
						ulong[] longArrayData;
						size_t sz;
						void addExp(ir.Exp e)
						{
							auto constant = cast(ir.Constant) e;
							if (constant !is null) {
								if (sz == 0) {
									sz = size(ss.location, ctx.lp, constant.type);
									assert(sz > 0);
								}
								switch (sz) {
								case 8:
									longArrayData ~= constant._ulong;
									break;
								default:
									intArrayData ~= constant._uint;
									break;
								}
								return;
							}
							auto cexp = cast(ir.Unary) e;
							if (cexp !is null) {
								assert(cexp.op == ir.Unary.Op.Cast);
								assert(sz == 0);
								sz = size(ss.location, ctx.lp, cexp.type);
								assert(sz == 8);
								addExp(cexp.value);
								return;
							}

							auto type = getExpType(ctx.lp, exp, ctx.current);
							throw makeSwitchBadType(ss, type);
						}
						foreach (e; alit.values) {
							addExp(e);
						}
						if (sz == 8) {
							h = hash(longArrayData.ptr, longArrayData.length * ulong.sizeof);
						} else {
							h = hash(intArrayData.ptr, intArrayData.length * uint.sizeof);
						}
					}
					if (auto p = h in arrayCases) {
						auto aStatements = _case.statements.statements;
						auto bStatements = p._case.statements.statements;
						auto c = p._case.statements.myScope;
						auto aBlock = buildBlockStat(exp.location, p._case.statements, c, aStatements);
						auto bBlock = buildBlockStat(exp.location, p._case.statements, c, bStatements);
						p._case.statements.statements.length = 0;

						auto cmp = buildBinOp(exp.location, ir.BinOp.Op.Equal, copyExp(exp), copyExp(originalCondition));
						auto ifs = buildIfStat(exp.location, p._case.statements, cmp, aBlock, bBlock);
						p._case.statements.statements[0] = ifs;
						if (p.lastIf !is null) {
							p.lastIf.thenState.myScope.parent = ifs.elseState.myScope;
							p.lastIf.elseState.myScope.parent = ifs.elseState.myScope;
						}
						p.lastIf = ifs;
						toRemove ~= i;
					} else {
						arrayCases[h] = ArrayCase(exp, _case, null);
					}
					exp = buildConstantUint(exp.location, h);
				}
			}
		}
		if (_case.firstExp !is null) {
			replaceWithHashIfNeeded(_case.firstExp);
			extypeAssign(ctx, _case.firstExp, conditionType);
		}
		if (_case.secondExp !is null) {
			replaceWithHashIfNeeded(_case.secondExp);
			extypeAssign(ctx, _case.secondExp, conditionType);
		}
		foreach (ref exp; _case.exps) {
			replaceWithHashIfNeeded(exp);
			extypeAssign(ctx, exp, conditionType);
		}
	}

	for (int i = cast(int) toRemove.length - 1; i >= 0; i--) {
		ss.cases = remove(ss.cases, toRemove[i]);
	}

	auto asEnum = cast(ir.Enum) conditionType;
	if (asEnum is null && ss.isFinal) {
		throw makeExpected(ss, "enum type for final switch");
	}
	if (ss.isFinal && ss.cases.length != asEnum.members.length) {
		throw makeFinalSwitchBadCoverage(ss);
	}
}

/**
 * Check a given Aggregate's anonymous structs/unions
 * (if any) for name collisions.
 */
void checkAnonymousVariables(Context ctx, ir.Aggregate agg)
{
	if (agg.anonymousAggregates.length == 0) {
		return;
	}
	bool[string] names;
	foreach (anonAgg; agg.anonymousAggregates) foreach (n; anonAgg.members.nodes) {
		auto var = cast(ir.Variable) n;
		auto fn = cast(ir.Function) n;
		string name;
		if (var !is null) {
			name = var.name;
		} else if (fn !is null) {
			name = fn.name;
		} else {
			continue;
		}
		if ((name in names) !is null) {
			throw makeAnonymousAggregateRedefines(anonAgg, name);
		}
		auto store = lookupAsThisScope(ctx.lp, agg.myScope, agg.location, name);
		if (store !is null) {
			throw makeAnonymousAggregateRedefines(anonAgg, name);
		}
	}
}

/// Turn a runtime assert into an if and a throw.
ir.Node transformRuntimeAssert(Context ctx, ir.AssertStatement as)
{
	if (as.isStatic) {
		throw panic(as.location, "expected runtime assert");
	}
	auto l = as.location;
	ir.Exp message = as.message;
	if (message is null) {
		message = buildStringConstant(l, "\"assertion failure\"");
	}
	assert(message !is null);
	auto exception = buildNew(l, ctx.lp.assertErrorClass, "AssertError", message);
	auto theThrow  = buildThrowStatement(l, exception);
	auto thenBlock = buildBlockStat(l, null, ctx.current, theThrow);
	auto ifS = buildIfStat(l, buildNot(l, as.condition), thenBlock);
	return ifS;
}

void transformArrayLiteralIfNeeded(Context ctx, ref ir.Exp exp, ir.ArrayLiteral al)
{
	size_t constants;
	foreach (e; al.values) {
		if (e.isConstant) {
			constants++;
		}
	}
	if (!ctx.isInFunction) {
		if (constants != al.values.length) {
			throw makeExpected(al.location, "constant array");
		}
		return;
	}
	if (constants == al.values.length) {
		return;
	}
	auto at = getExpType(ctx.lp, al, ctx.current);
	exp = buildInternalArrayLiteralSmart(al.location, at, al.values);
}

/**
 * Rewrites a given foreach statement (fes) into a for statement.
 * The ForStatement create takes several nodes directly; that is
 * to say, the original foreach and the new for cannot coexist.
 */
ir.ForStatement foreachToFor(ir.ForeachStatement fes, Context ctx, ir.Scope nestedScope, ref int aggregateForeaches, out string[] replacers, out ir.Function nestedFunction)
{
	auto l = fes.location;
	auto fs = new ir.ForStatement();
	fs.location = l;
	panicAssert(fes, fes.itervars.length == 1 || fes.itervars.length == 2);
	fs.initVars = fes.itervars;
	fs.block = fes.block;

	// foreach (i; 5 .. 7) => for (int i = 5; i < 7; i++)
	// foreach_reverse (i; 5 .. 7) => for (int i = 7 - 1; i >= 5; i--)
	if (fes.beginIntegerRange !is null) {
		panicAssert(fes, fes.endIntegerRange !is null);
		panicAssert(fes, fes.itervars.length == 1);
		auto v = fs.initVars[0];
		if (v.type is null) {
			v.type = buildInt(v.location);
		}
		v.assign = fes.reverse ?
			buildSub(l, fes.endIntegerRange, buildConstantInt(l, 1)) :
			fes.beginIntegerRange;

		auto cmpRef = buildExpReference(v.location, v, v.name);
		auto incRef = buildExpReference(v.location, v, v.name);
		fs.test = buildBinOp(l,
							 fes.reverse ? ir.BinOp.Op.GreaterEqual : ir.BinOp.Op.Less,
							 cmpRef, fes.reverse ? fes.beginIntegerRange : fes.endIntegerRange);
		fs.increments ~= fes.reverse ? buildDecrement(v.location, incRef) :
						 buildIncrement(v.location, incRef);
		return fs;
	}

	auto aggType = realType(getExpType(ctx.lp, fes.aggregate, ctx.current), true, true);

	ensureResolved(ctx.lp, ctx.current, aggType);

	// foreach (i, e; array) => for (size_t i = 0; i < array.length; i++) auto e = array[i]; ...
	// foreach_reverse (i, e; array) => for (size_t i = array.length - 1; i+1 >= 0; i--) auto e = array[i]; ..
	if (aggType.nodeType == ir.NodeType.ArrayType) {
		// i = 0 / i = array.length
		ir.Variable indexVar, elementVar;
		ir.Exp indexAssign;
		if (!fes.reverse) {
			indexAssign = buildSizeTConstant(l, ctx.lp, 0);
		} else {
			indexAssign = buildSub(l, buildAccess(l, fes.aggregate, "length"), buildConstantInt(l, 1));
		}
		if (fs.initVars.length == 2) {
			indexVar = fs.initVars[0];
			if (indexVar.type is null) {
				indexVar.type = ctx.lp.settings.getSizeT(l);
			}
			indexVar.assign = copyExp(indexAssign);
			elementVar = fs.initVars[1];
		} else {
			panicAssert(fes, fs.initVars.length == 1);
			indexVar = buildVariable(l, ctx.lp.settings.getSizeT(l),
									 ir.Variable.Storage.Function, "i", indexAssign);
			elementVar = fs.initVars[0];
			fs.initVars ~= indexVar;
		}

		auto st = cast(ir.StorageType) elementVar.type;
		if (st !is null && st.type == ir.StorageType.Kind.Ref) {
			ir.Exp dg(Location l)
			{
				return buildIndex(l, fes.aggregate, buildExpReference(l, indexVar, indexVar.name));
			}
			ctx.current.addExpressionDelegate(elementVar, &dg, elementVar.name);
			st = cast(ir.StorageType) st.base;
		}
		if (st !is null && st.type == ir.StorageType.Kind.Auto) {
			auto asArray = cast(ir.ArrayType) aggType;
			panicAssert(fes, asArray !is null);
			ensureResolved(ctx.lp, ctx.current, elementVar.type);
			elementVar.type = copyTypeSmart(asArray.base.location, asArray.base);
			assert(elementVar.type !is null);
		}

		// i < array.length / i + 1 >= 0
		auto tref = buildExpReference(indexVar.location, indexVar, indexVar.name);
		auto rtref = buildAdd(l, tref, buildConstantInt(l, 1));
		auto length = buildAccess(l, copyExp(fes.aggregate), "length");
		auto zero = buildSizeTConstant(l, ctx.lp, 0);
		fs.test = buildBinOp(l, fes.reverse ? ir.BinOp.Op.NotEqual : ir.BinOp.Op.Less,
							 fes.reverse ? rtref : tref,
							 fes.reverse ? zero : length);

		// auto e = array[i]; i++/i--
		auto incRef = buildExpReference(indexVar.location, indexVar, indexVar.name);
		auto accessRef = buildExpReference(indexVar.location, indexVar, indexVar.name);
		auto eRef = buildExpReference(elementVar.location, elementVar, elementVar.name);
		auto assign = buildAssign(incRef.location, eRef,
								  buildIndex(incRef.location, fes.aggregate, accessRef));
		fs.block.statements = buildExpStat(assign.location, assign) ~ fs.block.statements;
		fs.increments ~= fes.reverse ? buildDecrement(incRef.location, incRef) :
									   buildIncrement(incRef.location, incRef);
		return fs;
	}

	// foreach (i; aStructOrClass) { ... } => int dg(ref int i) { ... } for (;aStructOrClass.opApply(dg);) {}
	// foreach_reverse (i; aStructOrClass) { ... } => int dg(ref int i) { ... } for (;aStructOrClass.opApplyReverse(dg);) {}
	auto agg = cast(ir.Aggregate) aggType;
	if (agg !is null) {
		auto fn = buildFunction(l, nestedScope, "fndg", true);
		fn._body.myScope.nestedDepth = nestedScope.nestedDepth + 1;
		fn.kind = ir.Function.Kind.Member;
		fn.type.ret = buildInt(l);
		auto st = buildStorageType(l, ir.StorageType.Kind.Ref, buildInt(l));
		assert(fn.params.length == 0);

		// Adjacent foreaches end up in the same nested struct, so these vars need unique names.
		auto newName = format("%s%s", aggregateForeaches++, fs.initVars[0].name);
		addParam(l, fn, st, newName);
		auto replacer = new IdentifierExpReplacer(fs.initVars[0].name, newName);
		accept(fes, replacer);

		foreach (node; fes.block.statements) {
			auto bstat = cast(ir.BreakStatement) node;
			if (bstat !is null) {
				buildReturnStat(l, fn._body, buildConstantInt(l, 1));
				continue;
			}
			auto cstat = cast(ir.ContinueStatement) node;
			if (cstat !is null) {
				buildReturnStat(l, fn._body, buildConstantInt(l, 0));
				continue;
			}
			fn._body.statements ~= node;
		}
		buildReturnStat(l, fn._body, buildConstantInt(l, 0));
		nestedFunction = fn;
		auto simplefs = new ir.ForStatement();
		simplefs.location = l;
		ir.Exp[] args = [buildExpReference(l, fn, fn.name)];
		simplefs.test = buildCall(l, buildAccess(l, fes.aggregate, fes.reverse ? "opApplyReverse" : "opApply"), args);
		simplefs.block = fes.block;
		simplefs.block.statements.length = 0;
		return simplefs;
	}

	// foreach (k, v; aa) => for (size_t i; i < aa.keys.length; i++) k = aa.keys[i]; v = aa[k];
	// foreach_reverse => error, as order is undefined.
	auto aa = cast(ir.AAType) aggType;
	if (aa !is null) {
		if (fes.reverse) {
			throw makeForeachReverseOverAA(fes);
		}
		if (fs.initVars.length != 1 && fs.initVars.length != 2) {
			throw makeExpected(fes.location, "1 or 2 iteration variables");
		}

		auto valVar = fs.initVars[0];
		ir.Variable keyVar;
		if (fs.initVars.length == 2) {
			keyVar = valVar;
			valVar = fs.initVars[1];
		} else {
			keyVar = buildVariable(l, null, ir.Variable.Storage.Function, format("%sk", fs.block.myScope.nestedDepth));
			fs.initVars ~= keyVar;
		}

		auto vstor = cast(ir.StorageType) valVar.type;
		if (vstor !is null && vstor.type == ir.StorageType.Kind.Auto) {
			valVar.type = null;
		}

		auto kstor = cast(ir.StorageType) keyVar.type;
		if (kstor !is null && kstor.type == ir.StorageType.Kind.Auto) {
			keyVar.type = null;
		}

		if (valVar.type is null) {
			valVar.type = copyTypeSmart(l, aa.value);
		}
		if (keyVar.type is null) {
			keyVar.type = copyTypeSmart(l, aa.key);
		}
		auto indexVar = buildVariable(l, ctx.lp.settings.getSizeT(l), ir.Variable.Storage.Function, format("%si", fs.block.myScope.nestedDepth), buildSizeTConstant(l, ctx.lp, 0));
		assert(keyVar.type !is null);
		assert(valVar.type !is null);
		assert(indexVar.type !is null);
		fs.initVars ~= indexVar;

		// i < aa.keys.length
		auto index = buildExpReference(l, indexVar, indexVar.name);
		auto len = buildAccess(l, buildAccess(l, copyExp(fes.aggregate), "keys"), "length");
		fs.test = buildBinOp(l, ir.BinOp.Op.Less, index, len);

		// k = aa.keys[i]
		auto kref = buildExpReference(l, keyVar, keyVar.name);
		auto keys = buildAccess(l, copyExp(fes.aggregate), "keys");
		auto rh   = buildIndex(l, keys, buildExpReference(l, indexVar, indexVar.name));
		fs.increments ~= buildAssign(l, kref, rh);

		// v = aa[aa.keys[i]]
		fs.increments ~= buildAssign(l, buildExpReference(l, valVar, valVar.name), buildIndex(l, copyExp(fes.aggregate), buildIndex(l, buildAccess(l, copyExp(fes.aggregate), "keys"), buildExpReference(l, indexVar, indexVar.name))));

		// i++
		fs.increments ~= buildIncrement(l, buildExpReference(l, indexVar, indexVar.name));

		return fs;
	}


	throw makeExpected(l, "foreach aggregate type");
}

/**
 * If type casting were to be strict, type T could only
 * go to type T without an explicit cast. Implicit casts
 * are places where the language deems automatic conversion
 * safe enough to insert casts for the user.
 *
 * Thus, the primary job of extyper ('explicit typer') is
 * to insert casts where an implicit conversion has taken place.
 *
 * The second job of extyper is to make any implicit or
 * inferred types or expressions concrete -- for example,
 * to make const i = 2 become const int = 2.
 */
class ExTyper : NullVisitor, Pass
{
public:
	bool enterFirstVariable;
	int nestedDepth;
	Context ctx;

public:
	override void transform(ir.Module m)
	{
		accept(m, this);
	}

	/**
	 * For out of band checking of Variables.
	 */
	void transform(ir.Scope current, ir.Variable v)
	{
		ctx.setupFromScope(current);
		scope (exit) ctx.reset();

		this.enterFirstVariable = true;
		accept(v, this);
	}

	/**
	 * For out of band checking of UserAttributes.
	 */
	void transform(ir.Scope current, ir.Attribute a)
	{
		ctx.setupFromScope(current);
		scope (exit) ctx.reset();

		basicValidateUserAttribute(ctx.lp, ctx.current, a);

		auto ua = a.userAttribute;
		assert(ua !is null);

		foreach (i, ref arg; a.arguments) {
			extypeAssign(ctx, a.arguments[i], ua.fields[i].type);
			acceptExp(a.arguments[i], this);
		}
	}

	void transform(ir.Scope current, ir.EnumDeclaration ed)
	{
		ctx.setupFromScope(current);
		scope (exit) ctx.reset();

		ensureResolved(ctx.lp, ctx.current, ed.type);

		ir.EnumDeclaration[] edStack;
		ir.Exp prevExp;

		do {
			edStack ~= ed;
			if (ed.assign !is null) {
				break;
			}

			ed = ed.prevEnum;
			if (ed is null) {
				break;
			}

			if (ed.resolved) {
				prevExp = ed.assign;
				break;
			}
		} while (true);

		foreach_reverse (e; edStack) {
			resolve(e, prevExp);
			prevExp = e.assign;
		}
	}

	void resolve(ir.EnumDeclaration ed, ir.Exp prevExp)
	{
		ensureResolved(ctx.lp, ctx.current, ed.type);

		if (ed.assign is null) {
			if (prevExp is null) {
				ed.assign = buildConstantInt(ed.location, 0);
			} else {
				auto loc = ed.location;
				auto prevType = getExpType(ctx.lp, prevExp, ctx.current);
				if (!isIntegral(prevType)) {
					throw makeTypeIsNot(ed, prevType, buildInt(ed.location));
				}

				ed.assign = evaluate(ctx.lp, ctx.current, buildAdd(loc, copyExp(prevExp), buildConstantInt(loc, 1)));
			}
		} else {
			acceptExp(ed.assign, this);
			if (needsEvaluation(ed.assign)) {
				ed.assign = evaluate(ctx.lp, ctx.current, ed.assign);
			}
		}

		extypeAssign(ctx, ed.assign, ed.type);
		replaceStorageIfNeeded(ed.type);
		accept(ed.type, this);

		ed.resolved = true;
	}

	override void close()
	{
	}

	override Status enter(ir.Module m)
	{
		ctx.enter(m);
		return Continue;
	}

	override Status leave(ir.Module m)
	{
		ctx.leave(m);
		return Continue;
	}

	override Status enter(ir.Alias a)
	{
		ctx.lp.resolve(a);
		return ContinueParent;
	}

	override Status enter(ir.Struct s)
	{
		ctx.lp.actualize(s);
		ctx.enter(s);
		return Continue;
	}

	override Status leave(ir.Struct s)
	{
		checkAnonymousVariables(ctx, s);
		ctx.leave(s);
		return Continue;
	}

	override Status enter(ir._Interface i)
	{
		ctx.enter(i);
		return Continue;
	}

	override Status leave(ir._Interface i)
	{
		ctx.leave(i);
		return Continue;
	}

	override Status enter(ir.Union u)
	{
		ctx.lp.actualize(u);
		ctx.enter(u);
		return Continue;
	}

	override Status leave(ir.Union u)
	{
		checkAnonymousVariables(ctx, u);
		ctx.leave(u);
		return Continue;
	}

	override Status enter(ir.Class c)
	{
		ctx.lp.actualize(c);
		ctx.enter(c);
		return Continue;
	}

	override Status leave(ir.Class c)
	{
		checkAnonymousVariables(ctx, c);
		ctx.leave(c);
		return Continue;
	}

	override Status enter(ir.Enum e)
	{
		ctx.lp.resolve(e);
		ctx.enter(e);
		return Continue;
	}

	override Status leave(ir.Enum e)
	{
		ctx.leave(e);
		return Continue;
	}

	override Status enter(ir.UserAttribute ua)
	{
		ctx.lp.actualize(ua);
		// Everything is done by actualize.
		return ContinueParent;
	}

	override Status enter(ir.EnumDeclaration ed)
	{
		ctx.lp.resolve(ctx.current, ed);
		return ContinueParent;
	}

	override Status enter(ir.StorageType st)
	{
		ensureResolved(ctx.lp, ctx.current, st);
		assert(st.isCanonical);
		return Continue;
	}

	override Status enter(ir.FunctionParam p)
	{
		ensureResolved(ctx.lp, ctx.current, p.type);
		return Continue;
	}

	override Status enter(ir.Variable v)
	{
		ctx.isVarAssign = true;
		scope (exit) ctx.isVarAssign = false;
		// This has to be done this way, because the order in
		// which the calls in this and the visiting functions
		// are exectuted matters.
		if (!enterFirstVariable) {
			v.hasBeenDeclared = true;
			ctx.lp.resolve(ctx.current, v);
			if (v.assign !is null) {
				rejectBadScopeAssign(ctx, v.assign, v.type);
			}
			return ContinueParent;
		}
		enterFirstVariable = true;

		ensureResolved(ctx.lp, ctx.current, v.type);

		bool inAggregate = (cast(ir.Aggregate) ctx.current.node) !is null;
		if (inAggregate && v.storage != ir.Variable.Storage.Local && v.storage != ir.Variable.Storage.Global) {
			if (v.assign !is null) {
				auto _class = cast(ir.Class) ctx.current.node;
				if (_class !is null) {
					foreach (ctor; _class.userConstructors) {
						assert(ctor.thisHiddenParameter !is null);
						auto eref = buildExpReference(ctor.thisHiddenParameter.location, ctor.thisHiddenParameter, ctor.thisHiddenParameter.name);
						auto assign = buildAssign(ctor.location, buildAccess(ctor.location, eref, v.name), v.assign);
						auto stat = new ir.ExpStatement();
						stat.location = ctor.location;
						stat.exp = copyExp(assign);
						ctor._body.statements = stat ~ ctor._body.statements;
					}
					v.assign = null;
				} else {
					throw makeAssignToNonStaticField(v);
				}
			}
			if (isConst(v.type) || isImmutable(v.type)) {
				throw makeConstField(v);
			}
		}

		replaceTypeOfIfNeeded(ctx, v.type);

		if (v.assign !is null) {
			acceptExp(v.assign, this);
			extypeAssign(ctx, v.assign, v.type);
		}

		replaceStorageIfNeeded(v.type);
		accept(v.type, this);

		return ContinueParent;
	}

	override Status enter(ir.Function fn)
	{
		if (fn.name == "main" && fn.type.linkage == ir.Linkage.Volt) {
			if (fn.params.length == 0) {
				addParam(fn.location, fn, buildStringArray(fn.location), "");
			} else if (fn.params.length > 1) {
				throw makeInvalidMainSignature(fn);
			}
			if (!isVoid(fn.type.ret) && !isInt(fn.type.ret)) {
				throw makeInvalidMainSignature(fn);
			}
		}
		if (fn.nestStruct !is null && fn.thisHiddenParameter !is null && !ctx.isFunction) {
			auto cvar = copyVariableSmart(fn.thisHiddenParameter.location, fn.thisHiddenParameter);
			addVarToStructSmart(fn.nestStruct, cvar);
		}
		handleNestedThis(fn);
		handleNestedParams(ctx, fn);
		ctx.lp.resolve(ctx.current, fn);
		ctx.enter(fn);
		return Continue;
	}

	override Status leave(ir.Function fn)
	{
		if (fn.name == "main" && fn.type.linkage == ir.Linkage.Volt) {
			if (fn.params.length != 1) {
				throw panic(fn.location, "unnormalised main");
			}
			auto arr = cast(ir.ArrayType) fn.type.params[0];
			if (arr is null || !isString(realType(arr.base))) {
				throw makeInvalidMainSignature(fn);
			}
		}
		ctx.leave(fn);
		return Continue;
	}

	/*
	 *
	 * Statements.
	 *
	 */


	override Status enter(ir.WithStatement ws)
	{
		auto e = cast(ir.Unary) ws.exp;
		auto type = getExpType(ctx.lp, ws.exp, ctx.current);
		if (e !is null && realType(type).nodeType == ir.NodeType.Class) {
			auto var = buildVariableSmart(ws.block.location, type, ir.Variable.Storage.Function, ws.block.myScope.genAnonIdent());
			var.assign = e;
			ws.block.statements = var ~ ws.block.statements;
			ws.exp = buildExpReference(var.location, var, var.name);
		}
		return Continue;
	}

	override Status enter(ir.ReturnStatement ret)
	{
		auto fn = getParentFunction(ctx.current);
		if (fn is null) {
			throw panic(ret, "return statement outside of function.");
		}

		if (ret.exp !is null) {
			acceptExp(ret.exp, this);
			extypeAssign(ctx, ret.exp, fn.type.ret);
		}

		return ContinueParent;
	}

	override Status enter(ir.IfStatement ifs)
	{
		if (ifs.exp !is null) {
			acceptExp(ifs.exp, this);
			extypeCastToBool(ctx, ifs.exp);
		}

		if (ifs.thenState !is null) {
			accept(ifs.thenState, this);
		}

		if (ifs.elseState !is null) {
			accept(ifs.elseState, this);
		}

		return ContinueParent;
	}

	override Status enter(ir.ForeachStatement fes)
	{
		return ContinueParent;
	}

	override Status enter(ir.ForStatement fs)
	{
		ctx.enter(fs.block);
		foreach (i; fs.initVars) {
			accept(i, this);
		}
		foreach (ref i; fs.initExps) {
			acceptExp(i, this);
		}

		if (fs.test !is null) {
			acceptExp(fs.test, this);
			extypeCastToBool(ctx, fs.test);
		}
		foreach (ref increment; fs.increments) {
			acceptExp(increment, this);
		}
		foreach (ctxment; fs.block.statements) {
			accept(ctxment, this);
		}
		ctx.leave(fs.block);

		return ContinueParent;
	}

	override Status enter(ir.WhileStatement ws)
	{
		if (ws.condition !is null) {
			acceptExp(ws.condition, this);
			extypeCastToBool(ctx, ws.condition);
		}

		accept(ws.block, this);

		return ContinueParent;
	}

	override Status enter(ir.DoStatement ds)
	{
		accept(ds.block, this);

		if (ds.condition !is null) {
			acceptExp(ds.condition, this);
			extypeCastToBool(ctx, ds.condition);
		}

		return ContinueParent;
	}

	override Status enter(ir.SwitchStatement ss)
	{
		verifySwitchStatement(ctx, ss);
		return Continue;
	}

	override Status leave(ir.ThrowStatement t)
	{
		extypeThrow(ctx, t);
		return Continue;
	}

	override Status enter(ir.AssertStatement as)
	{
		if (!as.isStatic) {
			return Continue;
		}
		auto cond = cast(ir.Constant) as.condition;
		auto msg = cast(ir.Constant) as.message;
		if ((cond is null || msg is null) || (!isBool(cond.type) || !isString(msg.type))) {
			throw panicUnhandled(as, "non simple static asserts (bool and string literal only).");
		}
		if (!cond._bool) {
			throw makeStaticAssert(as, msg._string);
		}
		return Continue;
	}

	override Status enter(ir.BlockStatement bs)
	{
		ctx.enter(bs);
		// Translate runtime asserts before processing the block.
		for (size_t i = 0; i < bs.statements.length; i++) {
			auto as = cast(ir.AssertStatement) bs.statements[i];
			if (as is null || as.isStatic) {
				continue;
			}
			bs.statements[i] = transformRuntimeAssert(ctx, as);
		}
		return Continue;
	}

	override Status leave(ir.BlockStatement bs)
	{
		ir.Function nestedFunction;
		ir.ForeachStatement lastFes;
		int aggregateForeaches;
		for (size_t i = 0; i < bs.statements.length; i++) {
			auto fes = cast(ir.ForeachStatement) bs.statements[i];
			if (fes is null) {
				continue;
			}
			assert(fes !is lastFes);
			lastFes = fes;
			string[] replacers;
			auto forStatement = foreachToFor(fes, ctx, ctx.current, aggregateForeaches, replacers, nestedFunction);
			int toAdd = 1;

			if (nestedFunction !is null) {
				if (ctx.currentFunction.nestStruct is null) {
					toAdd += 2;
					ctx.currentFunction.nestStruct = createAndAddNestedStruct(ctx.currentFunction, bs);
					ctx.currentFunction.nestStruct.myScope = new ir.Scope(ctx.currentFunction.myScope, ctx.currentFunction.nestStruct, "__Nested");
				}
				auto ns = ctx.currentFunction.nestStruct;
				assert(ns !is null);
				assert(ns.myScope !is null);
				auto tr = buildTypeReference(ns.location, ns, "__Nested");
				auto decl = buildVariable(nestedFunction.location, tr, ir.Variable.Storage.Function, "__nested");
				if (nestedFunction.nestedHiddenParameter is null) {
					nestedFunction.nestedHiddenParameter = decl;
					nestedFunction.nestedVariable = decl;
					nestedFunction.nestStruct = ns;
					nestedFunction.type.hiddenParameter = true;
				}
				bs.statements.insertInPlace(i, nestedFunction);
				accept(bs.statements[i], this);
				auto l = forStatement.location;
				auto _call = cast(ir.Postfix) forStatement.test;
				assert(_call !is null);
				assert(_call.arguments.length == 1);
				_call.arguments[0] = buildCreateDelegate(l, buildExpReference(l, ctx.currentFunction.nestedVariable), buildExpReference(l, nestedFunction));
				i += toAdd;  // nested struct + nested struct variable + nested function = 3
			}
			bs.statements[i] = forStatement;
			accept(bs.statements[i], this);
		}
		ctx.leave(bs);
		return Continue;
	}


	/*
	 *
	 * Types.
	 *
	 */


	override Status enter(ir.FunctionType ftype)
	{
		replaceTypeOfIfNeeded(ctx, ftype.ret);
		return Continue;
	}

	override Status enter(ir.DelegateType dtype)
	{
		replaceTypeOfIfNeeded(ctx, dtype.ret);
		return Continue;
	}
	enum Kind
	{
		Alias,
		Value,
		Type,
		Scope,
		Function,
		Template,
		EnumDeclaration,
		FunctionParam,
	}
	override Status enter(ref ir.Exp exp, ir.Typeid _typeid)
	{
		if (_typeid.ident.length > 0) {
			auto store = lookup(ctx.lp, ctx.current, _typeid.location, _typeid.ident);
			if (store is null) {
				throw makeFailedLookup(_typeid, _typeid.ident);
			}
			switch (store.kind) with (ir.Store.Kind) {
			case Type:
				_typeid.type = buildTypeReference(_typeid.location, cast(ir.Type) store.node, _typeid.ident);
				assert(_typeid.type !is null);
				break;
			case Value, EnumDeclaration, FunctionParam, Function:
				auto decl = cast(ir.Declaration) store.node;
				_typeid.exp = buildExpReference(_typeid.location, decl, _typeid.ident);
				break;
			default:
				throw panicUnhandled(_typeid, "store kind");
			}
			_typeid.ident.length = 0;
		}
		if (_typeid.exp !is null) {
			_typeid.type = getExpType(ctx.lp, _typeid.exp, ctx.current);
			if ((cast(ir.Aggregate) _typeid.type) !is null) {
				_typeid.type = buildTypeReference(_typeid.type.location, _typeid.type);
			} else {
				_typeid.type = copyType(_typeid.type);
			}
			_typeid.exp = null;
		}
		ensureResolved(ctx.lp, ctx.current, _typeid.type);
		replaceTypeOfIfNeeded(ctx, _typeid.type);
		return Continue;
	}

	/*
	 *
	 * Expressions.
	 *
	 */


	/// If this is an assignment to a @property function, turn it into a function call.
	override Status leave(ref ir.Exp e, ir.BinOp bin)
	{
		rewritePropertyFunctionAssign(ctx, e, bin);
		// If rewritten.
		if (e is bin) {
			extypeBinOp(ctx, bin, e);
		}
		return Continue;
	}

	override Status enter(ref ir.Exp exp, ir.Postfix postfix)
	{
		ctx.enter(postfix);
		extypePostfix(ctx, exp, postfix);
		return Continue;
	}

	override Status leave(ref ir.Exp exp, ir.Postfix postfix)
	{
		ctx.leave(postfix);
		extypeLeavePostfix(ctx, exp, postfix);
		return Continue;
	}


	override Status leave(ref ir.Exp exp, ir.Unary _unary)
	{
		if (_unary.type !is null) {
			ensureResolved(ctx.lp, ctx.current, _unary.type);
			replaceTypeOfIfNeeded(ctx, _unary.type);
		}
		extypeUnary(ctx, exp, _unary);
		return Continue;
	}

	override Status leave(ref ir.Exp exp, ir.Ternary ternary)
	{
		extypeTernary(ctx, ternary);
		return Continue;
	}

	override Status enter(ref ir.Exp exp, ir.TypeExp te)
	{
		ensureResolved(ctx.lp, ctx.current, te.type);
		return Continue;
	}

	override Status enter(ref ir.Exp exp, ir.VaArgExp vaexp)
	{
		ensureResolved(ctx.lp, ctx.current, vaexp.type);
		return Continue;
	}

	override Status leave(ref ir.Exp exp, ir.VaArgExp vaexp)
	{
		if (!isLValue(vaexp.arg)) {
			throw makeVaFooMustBeLValue(vaexp.arg.location, "va_exp");
		}
		if (ctx.currentFunction.type.linkage == ir.Linkage.C) {
			if (vaexp.type.nodeType != ir.NodeType.PrimitiveType && vaexp.type.nodeType != ir.NodeType.PointerType) {
				throw makeCVaArgsOnlyOperateOnSimpleTypes(vaexp.location);
			}
			vaexp.arg = buildAddrOf(vaexp.location, copyExp(vaexp.arg));
		} else {
			exp = buildVaArgCast(vaexp.location, vaexp);
		}
		return Continue;
	}

	override Status enter(ref ir.Exp exp, ir.ArrayLiteral al)
	{
		transformArrayLiteralIfNeeded(ctx, exp, al);
		return Continue;
	}

	override Status visit(ref ir.Exp exp, ir.ExpReference eref)
	{
		replaceExpReferenceIfNeeded(ctx, null, exp, eref);
		return Continue;
	}

	override Status visit(ref ir.Exp exp, ir.IdentifierExp ie)
	{
		auto oldexp = exp;
		if (!ie.globalLookup) {
			auto oldExp = exp;
			if (exp !is oldExp) {
				acceptExp(exp, this);
				return ContinueParent;
			}
		}

		extypeIdentifierExp(ctx, exp, ie);
		if (oldexp !is exp) {
			return acceptExp(exp, this);
		}
		return Continue;
	}

	override Status enter(ref ir.Exp exp, ir.Constant constant)
	{
		if (constant._string == "$" && isIntegral(constant.type)) {
			if (ctx.lastIndexChild is null) {
				throw makeDollarOutsideOfIndex(constant);
			}
			auto l = constant.location;
			// Rewrite $ to (arrayName.length).
			exp = buildAccess(l, copyExp(ctx.lastIndexChild), "length");
		}
		return Continue;
	}

	override Status visit(ref ir.Exp exp, ir.TokenExp fexp)
	{
		if (fexp.type == ir.TokenExp.Type.File) {
			string fname = fexp.location.filename;
			version (Windows) {
				string[dchar] transTable = ['\\': "/"];
				fname = translate(fname, transTable);
			}
			exp = buildStringConstant(fexp.location, `"` ~ fname ~ `"`); 
			return Continue;
		} else if (fexp.type == ir.TokenExp.Type.Line) {
			exp = buildConstantInt(fexp.location, cast(int) fexp.location.line);
			return Continue;
		}

		char[] buf = `"`.dup;
		void sink(string s)
		{
			buf ~= s;
		}
		auto pp = new PrettyPrinter("\t", &sink);

		string[] names;
		ir.Scope scop = ctx.current;
		ir.Function foundFunction;
		while (scop !is null) {
			if (scop.node.nodeType != ir.NodeType.BlockStatement) {
				names ~= scop.name;
			}
			if (scop.node.nodeType == ir.NodeType.Function) {
				foundFunction = cast(ir.Function) scop.node;
			}
			scop = scop.parent;
		}
		if (foundFunction is null) {
			throw makeFunctionNameOutsideOfFunction(fexp);
		}

		if (fexp.type == ir.TokenExp.Type.PrettyFunction) {
			pp.transform(foundFunction.type.ret);
			buf ~= " ";
		}

		foreach_reverse (i, name; names) {
			buf ~= name ~ (i > 0 ? "." : "");
		}

		if (fexp.type == ir.TokenExp.Type.PrettyFunction) {
			buf ~= "(";
			foreach (i, ptype; ctx.currentFunction.type.params) {
				pp.transform(ptype);
				if (i < ctx.currentFunction.type.params.length - 1) {
					buf ~= ", ";
				}
			}
			buf ~= ")";
		}

		buf ~= "\"";

		exp = buildStringConstant(fexp.location, buf.idup);
		return Continue;
	}

public:
	this(LanguagePass lp)
	{
		ctx = new Context(lp);
		ctx.etyper = this;
	}
}
