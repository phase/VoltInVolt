// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module volt.interfaces;

import volt.token.location;
import volt.ir.ir;


/**
 * Home to logic for tying Frontend, Pass and Backend together and
 * abstracts away several IO related functions. Such as looking up
 * module files and printing error messages.
 */
class Controller
{
	Module getModule(QualifiedName name);

	void close();
}

/**
 * Start of the compile pipeline, it lexes source, parses tokens and do
 * some very lightweight transformation of internal AST into Volt IR.
 */
class Frontend
{
	Module parseNewFile(string source, Location loc);

	/**
	 * Parse a zero or more statements from a string, does not
	 * need to start with '{' or end with a '}'.
	 *
	 * Used for string mixins in functions.
	 */
	Node[] parseStatements(string source, Location loc);

	void close();
}

/**
 * @defgroup passes Passes
 * @brief Volt is a passes based compiler.
 */

/**
 * Interface implemented by transformation, debug and/or validation passes.
 *
 * Transformation passes often lowers high level Volt IR into something
 * that is easier for backends to handle.
 *
 * Validation passes validates the Volt IR, and reports errors, often halting
 * compilation by throwing CompilerError.
 *
 * @ingroup passes
 */
class Pass
{
	void transform(Module m);

	void close();
}

/**
 * @defgroup passLang Language Passes
 * @ingroup passes
 * @brief Language Passes verify and slightly transforms parsed modules.
 *
 * The language passes are devided into 3 main phases:
 * 1. PostParse
 * 2. Exp Type Verification
 * 3. Misc
 *
 * Phase 1, PostParse, works like this:
 * 1. All of the version statements are resolved for the ent module.
 * 2. Then for each Module, Class, Struct, Enum's TopLevelBlock.
 *   1. Apply all attributes in the current block or dct children.
 *   2. Add symbols to scope in the current block or dct children.
 *   3. Then do step a-c for for each child TopLevelBlock that
 *      brings in a new scope (Classes, Enums, Structs).
 * 3. Resolve the imports.
 * 4. Going from top to bottom resolving static if (applying step 2
 *    to the selected TopLevelBlock).
 *
 * Phase 2, ExpTyper, is just a single complex step that resolves and typechecks
 * any expressions, this pass is only run for modules that are called
 * dctly by the LanguagePass.transform function, or functions that
 * are invoked by static ifs.
 *
 * Phase 3, Misc, are various lowering and transformation passes, some can
 * inoke Phase 1 and 2 on newly generated code.
 */

/**
 * Center point for all language passes.
 * @ingroup passes passLang
 */
abstract class LanguagePass
{
public:
	Settings settings;
	Frontend frontend;
	Controller controller;

	/**
	 * Cached lookup items.
	 * @{
	 */
	Module objectModule;
	Class objectClass;
	Class typeInfoClass;
	Class attributeClass;
	Struct arrayStruct;
	Variable allocDgVariable;
	Function vaStartFunc;
	Function vaEndFunc;
	Function vaCStartFunc;
	Function vaCEndFunc;
	Function memcpyFunc;
	Function throwSliceErrorFunction;
	/* @} */

	/**
	 * Type id constants for TypeInfo.
	 * @{
	 */
	EnumDeclaration TYPE_STRUCT;
	EnumDeclaration TYPE_CLASS;
	EnumDeclaration TYPE_INTERFACE;
	EnumDeclaration TYPE_UNION;
	EnumDeclaration TYPE_ENUM;
	EnumDeclaration TYPE_ATTRIBUTE;
	EnumDeclaration TYPE_USER_ATTRIBUTE;

	EnumDeclaration TYPE_VOID;
	EnumDeclaration TYPE_UBYTE;
	EnumDeclaration TYPE_BYTE;
	EnumDeclaration TYPE_CHAR;
	EnumDeclaration TYPE_BOOL;
	EnumDeclaration TYPE_USHORT;
	EnumDeclaration TYPE_SHORT;
	EnumDeclaration TYPE_WCHAR;
	EnumDeclaration TYPE_UINT;
	EnumDeclaration TYPE_INT;
	EnumDeclaration TYPE_DCHAR;
	EnumDeclaration TYPE_FLOAT;
	EnumDeclaration TYPE_ULONG;
	EnumDeclaration TYPE_LONG;
	EnumDeclaration TYPE_DOUBLE;
	EnumDeclaration TYPE_REAL;

	EnumDeclaration TYPE_POINTER;
	EnumDeclaration TYPE_ARRAY;
	EnumDeclaration TYPE_STATIC_ARRAY;
	EnumDeclaration TYPE_AA;
	EnumDeclaration TYPE_FUNCTION;
	EnumDeclaration TYPE_DELEGATE;
	/* @} */

public:
	this(Settings settings, Frontend frontend, Controller controller)
	out {
		////assert(this.settings !is null);
		////assert(this.frontend !is null);
		////assert(this.controller !is null);
	}
	body {
		this.settings = settings;
		this.frontend = frontend;
		this.controller = controller;
	}

	abstract void close();

	/**
	 * Helper function, often just routed to the Controller.
	 */
	abstract Module getModule(QualifiedName name);

	/*
	 *
	 * Resolve functions.
	 *
	 */

	/**
	 * Gathers all the symbols and adds scopes where needed from
	 * the given block statement.
	 *
	 * This function is intended to be used for inserting new
	 * block statements into already gathered functions, for
	 * instance when processing mixin statemetns.
	 */
	abstract void gather(Scope current, BlockStatement bs);

	/**
	 * Resolves a Variable making it usable externaly.
	 *
	 * @throws CompilerError on failure to resolve variable.
	 */
	abstract void resolve(Scope current, Variable v);

	/**
	 * Resolves a Function making it usable externaly,
	 *
	 * @throws CompilerError on failure to resolve function.
	 */
	abstract void resolve(Scope current, Function fn);

	/**
	 * Resolves a unresolved TypeReference in the given scope.
	 * The TypeReference's type is set to the looked up type,
	 * should type be not null nothing is done.
	 */
	abstract void resolve(Scope s, TypeReference tr);

	/**
	 * Resolves a unresolved alias store, the store can
	 * change type to Type, either the field myAlias or
	 * type is set.
	 *
	 * @throws CompilerError on failure to resolve alias.
	 * @{
	 */
	abstract void resolve(Store s);
	abstract void resolve(Alias a);
	/* @} */

	/**
	 * Resovles a Attribute, for UserAttribute usages.
	 */
	abstract void resolve(Scope current, Attribute a);

	/**
	 * Resolves a Enum making it usable externaly.
	 *
	 * @throws CompilerError on failure to resolve the enum.
	 */
	abstract void resolve(Enum e);

	/**
	 * Resolves a EnumDeclaration setting its value.
	 *
	 * @throws CompilerError on failure to resolve the enum value.
	 */
	abstract void resolve(Scope current, EnumDeclaration ed);

	/**
	 * Resoltes a AAType and checks if the Key-Type is compatible
	 *
	 * @throws CompilerError on invalid Key-Type
	 */
	abstract void resolve(Scope current, AAType at);

	/**
	 * Resovles a Struct, done on lookup of it.
	 */
	final void resolve(Struct s)
	{ if (!s.isResolved) doResolve(s); }

	/**
	 * Resovles a Union, done on lookup of it.
	 */
	final void resolve(Union u)
	{ if (!u.isResolved) doResolve(u); }

	/**
	 * Resovles a Class, making sure the parent is populated.
	 */
	final void resolve(Class c)
	{ if (!c.isResolved) doResolve(c); }

	/**
	 * Resovles a UserAttribute, done on lookup of it.
	 */
	final void resolve(UserAttribute au)
	{ if (!au.isResolved) doResolve(au); }

	/**
	 * Actualize a Struct, making sure all its fields and methods
	 * are populated, and any embedded structs (not referenced
	 * via pointers) are resolved as well.
	 */
	final void actualize(Struct s)
	{ if (!s.isActualized) doActualize(s); }

	/**
	 * Actualize a Union, making sure all its fields and methods
	 * are populated, and any embedded structs (not referenced
	 * via pointers) are resolved as well.
	 */
	final void actualize(Union u)
	{ if (!u.isActualized) doActualize(u); }

	/**
	 * Actualize a Class, making sure all its fields and methods
	 * are populated, Any embedded structs (not referenced via
	 * pointers) are resolved as well. Parent classes are
	 * resolved to.
	 *
	 * Any lowering structs and internal variables are also
	 * generated by this function.
	 */
	final void actualize(Class c)
	{ if (!c.isActualized) doActualize(c); }

	/**
	 * Actualize a Class, making sure all its fields are
	 * populated, thus making sure it can be used for
	 * validation of annotations.
	 *
	 * Any lowering classes/structs and internal variables
	 * are also generated by this function.
	 */
	final void actualize(UserAttribute ua)
	{ if (!ua.isActualized) doActualize(ua); }


	/*
	 *
	 * General phases functions.
	 *
	 */

	abstract void phase1(Module m);

	abstract void phase2(Module[] m);

	abstract void phase3(Module[] m);


	/*
	 *
	 * Protected action functions.
	 *
	 */

protected:
	abstract void doResolve(Class c);
	abstract void doResolve(Union u);
	abstract void doResolve(Struct c);
	abstract void doResolve(UserAttribute ua);

	abstract void doActualize(Struct s);
	abstract void doActualize(Union u);
	abstract void doActualize(Class c);
	abstract void doActualize(UserAttribute ua);
}

/**
 * @defgroup passLower Lowering Passes
 * @ingroup passes
 * @brief Lowers before being passed of to backends.
 */

/**
 * Used to determin the output of the backend.
 */
enum TargetType
{
	DebugPrinting,
	LlvmBitcode,
	ElfObject,
	VoltCode,
	CCode,
}

/**
 * Interface implemented by backends. Often the last stage of the compile
 * pipe that is implemented in this compiler, optimization and linking
 * are often done outside of the compiler, either invoked dctly by us
 * or a build system.
 */
class Backend
{
	/**
	 * Return the supported target types.
	 */
	TargetType[] supported();

	/**
	 * Set the target file and output type. Backends usually only
	 * suppports one or two output types @see supported.
	 */
	void setTarget(string filename, TargetType type);

	/**
	 * Compile the given module. You need to have called setTarget before
	 * calling this function. setTarget needs to be called for each
	 * invocation of this function.
	 */
	void compile(Module m);

	void close();
}

/**
 * Each of these listed platforms corresponds
 * to a Version identifier.
 *
 * Posix and Windows are not listed here as they
 * they are available on multiple platforms.
 *
 * Posix on Linux and OSX.
 * Windows on MinGW.
 */
enum Platform
{
	MinGW,
	Linux,
	OSX,
	EMSCRIPTEN,
}

/**
 * Each of these listed architectures corresponds
 * to a Version identifier.
 */
enum Arch
{
	X86,
	X86_64,
	LE32, // Generic little endian
}

/**
 * Holds a set of compiler settings.
 *
 * Things like version/debug identifiers, warning mode,
 * debug/release, import paths, and so on.
 */
final class Settings
{
public:
	bool warningsEnabled; ///< The -w argument.
	bool debugEnabled; ///< The -d argument.
	bool noBackend; ///< The -S argument.
	bool noLink; ///< The -c argument
	bool emitBitCode; ///< The --emit-bitcode argument.
	bool noCatch; ///< The --no-catch argument.
	bool internalDebug; ///< The --internal-dbg argument.
	bool noStdLib; ///< The --no-stdlib argument.
	bool removeConditionalsOnly; ///< The -E argument.

	Platform platform;
	Arch arch;

	string execDir; ///< Set on create.
	string platformStr; ///< Derived from platform.
	string archStr; ///< Derived from arch.

	string linker; ///< The --linker argument

	string outputFile;
	string[] includePaths; ///< The -I arguments.

	string[] libraryPaths; ///< The -L arguements.
	string[] libraryFiles; ///< The -l arguments.

	string[] stdFiles; ///< The --stdlib-file arguements.
	string[] stdIncludePaths; ///< The --stdlib-I arguments.

private:
	/// If the ident exists and is true, it's set, if false it's reserved.
	bool[string] mVersionIdentifiers;
	/// If the ident exists, it's set.
	bool[string] mDebugIdentifiers;

public:
	this(string execDir)
	{
		setDefaultVersionIdentifiers();
		this.execDir = execDir;
	}

	final void processConfigs()
	{
		setVersionsFromOptions();
		replaceMacros();
	}

	final void replaceMacros()
	{
		for (size_t i = 0; i < includePaths.length; i++)
			includePaths[i] = replaceEscapes(includePaths[i]);
		for (size_t i = 0; i < libraryPaths.length; i++)
			libraryPaths[i] = replaceEscapes(libraryPaths[i]);
		for (size_t i = 0; i < libraryFiles.length; i++)
			libraryFiles[i] = replaceEscapes(libraryFiles[i]);
		for (size_t i = 0; i < stdFiles.length; i++)
			stdFiles[i] = replaceEscapes(stdFiles[i]);
		for (size_t i = 0; stdIncludePaths.length; i++)
			stdIncludePaths[i] = replaceEscapes(stdIncludePaths[i]);
	}

	final void setVersionsFromOptions()
	{
		final switch (platform) {
		case Platform.MinGW:
			platformStr = "mingw";
			setVersionIdentifier("Windows");
			setVersionIdentifier("MinGW");
			break;
		case Platform.Linux:
			platformStr = "linux";
			setVersionIdentifier("Linux");
			setVersionIdentifier("Posix");
			break;
		case Platform.OSX:
			platformStr = "osx";
			setVersionIdentifier("OSX");
			setVersionIdentifier("Posix");
			break;
		case Platform.EMSCRIPTEN:
			platformStr = "emscripten";
			setVersionIdentifier("Emscripten");
			break;
		}

		final switch (arch) {
		case Arch.X86:
			archStr = "x86";
			setVersionIdentifier("X86");
			setVersionIdentifier("LittleEndian");
			setVersionIdentifier("V_P32");
			break;
		case Arch.X86_64:
			archStr = "x86_64";
			setVersionIdentifier("X86_64");
			setVersionIdentifier("LittleEndian");
			setVersionIdentifier("V_P64");
			break;
		case Arch.LE32:
			archStr = "le32";
			setVersionIdentifier("LE32");
			setVersionIdentifier("LittleEndian");
			setVersionIdentifier("V_P32");
		}
	}

	final string replaceEscapes(string file)
	{
		auto e = "%@execd";
		auto a = "%@arch%";
		auto p = "%@platform%";
		size_t ret;

		size_t indexOf(string a, string b) { return 0; }
		string replace(string a, string b, string c) { return ""; }

		ret = indexOf(file, e);
		if (ret != size_t.max)
			file = replace(file, e, execDir);
		ret = indexOf(file, a);
		if (ret != size_t.max)
			file = replace(file, a, archStr);
		ret = indexOf(file, p);
		if (ret != size_t.max)
			file = replace(file, p, platformStr);

		return file;
	}

	/// Throws: Exception if ident is reserved.
	final void setVersionIdentifier(string ident)
	{
		/*if (auto p = ident in mVersionIdentifiers) {
			if (!(*p)) {
				throw new Exception("cannot set reserved identifier.");
			}
		}*/
		mVersionIdentifiers[ident] = true;
	}

	/// Doesn't throw, debug identifiers can't be reserved.
	final void setDebugIdentifier(string ident)
	{
		mDebugIdentifiers[ident] = true;
	}

	/**
	 * Check if a given version identifier is set.
	 * Params:
	 *   ident = the identifier to check.
	 * Returns: true if set, false otherwise.
	 */
	final bool isVersionSet(string ident)
	{
		//if (auto p = ident in mVersionIdentifiers) {
		//	return *p;
		//} else {
			return false;
		//}
	}

	/**
	 * Check if a given debug identifier is set.
	 * Params:
	 *   ident = the identifier to check.
	 * Returns: true if set, false otherwise.
	 */
	final bool isDebugSet(string ident)
	{
	//	return (ident in mDebugIdentifiers) !is null;
		return false;
	}

	final PrimitiveType getSizeT(Location loc)
	{
		PrimitiveType pt;
		if (isVersionSet("V_P64")) {
			pt = new PrimitiveType(PrimitiveType.Kind.Ulong);
		} else {
			pt = new PrimitiveType(PrimitiveType.Kind.Uint);
		}
		pt.location = loc;
		return pt;
	}

private:
	final void setDefaultVersionIdentifiers()
	{
		setVersionIdentifier("Volt");
		setVersionIdentifier("all");

		reserveVersionIdentifier("none");
	}

	/// Marks an identifier as unable to be set. Doesn't set the identifier.
	final void reserveVersionIdentifier(string ident)
	{
		mVersionIdentifiers[ident] = false;
	}
}

version (none) unittest
{
	auto settings = new Settings();
	//assert(!settings.isVersionSet("none"));
	//assert(settings.isVersionSet("all"));
	settings.setVersionIdentifier("foo");
	//assert(settings.isVersionSet("foo"));
	//assert(!settings.isDebugSet("foo"));
	settings.setDebugIdentifier("foo");
	//assert(settings.isDebugSet("foo"));

	try {
		settings.setVersionIdentifier("none");
	//	//assert(false);
	} catch (Exception e) {
	}
}
