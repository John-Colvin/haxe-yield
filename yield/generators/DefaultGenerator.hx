/*
 * The MIT License
 * 
 * Copyright (C)2017 Dimitri Pomier
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
#if macro
package yield.generators;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.Access;
import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.Position;
import haxe.macro.Expr.TypeDefinition;
import haxe.macro.Type;
import haxe.macro.Type.AbstractType;
import haxe.macro.Type.TypeParameter;
import haxe.macro.TypeTools;
import yield.generators.NameController;
import yield.parser.WorkEnv;
import yield.parser.WorkEnv.Scope;
import yield.parser.YieldSplitter.IteratorBlockData;
import yield.parser.idents.IdentChannel;
import yield.parser.idents.IdentData;
import yield.parser.idents.IdentOption;
import yield.parser.idents.IdentRef;
import yield.parser.idents.IdentType;
import yield.parser.tools.ExpressionTools;
import yield.parser.tools.FieldTools;
import yield.parser.tools.IdentCategory;

class DefaultGenerator
{
	
	private static var extraTypeCounter:UInt = 0;
	
	private static var typeDefinitionStack:Array<TypeDefinition> = [];
	
	public static function makeTypeDefinition (workEnv:WorkEnv): TypeDefinition {
		
		var iteratorClassName:String = NameController.extraTypeName(workEnv, ++extraTypeCounter);
		
		var c  = macro class $iteratorClassName { };
		c.pos  = workEnv.classType.pos;
		c.meta = workEnv.classType.meta.get().copy();
		
		return c;
	}
	
	/**
	 * Generate the extra-type representing the iterator blocks, then add it into the queue of type definition.
	 * @return Returns the expression which instantiates the generated extra-type.
	 */
	public static function add (ibd:IteratorBlockData, pos:Position, workEnv:WorkEnv): Expr {
		
		var bd:BuildingData = new BuildingData(workEnv.generatedIteratorClass, workEnv.getExtraTypePath(), ibd);
		
		initTypeMetas(bd, pos);
		initTypeParams(bd, workEnv, pos);
		
		initIteratorActions(bd, workEnv, pos);
		
		initParentDependencies(bd, workEnv, pos);
		initParentAsVarDependencies(bd, workEnv, pos);
		initInstanceDependency(bd, workEnv, pos);
		initIteratorInitialisations(bd, workEnv, ibd, pos);
		initIteratorMethods(bd, workEnv, ibd, pos);
		initConstructor(bd, pos);
		
		allowAccessToPrivateFields(workEnv, pos);
		initInstanceAccessions(workEnv);
		initParentAccessions(workEnv);
		
		initVariableFields(bd, workEnv);
		initIterativeFunctions(bd, workEnv, ibd);
		
		typeDefinitionStack.push( bd.typeDefinition );
		
		initInstanceFunctionBody(bd, pos);
		return bd.instanceFunctionBody;
	}
	
	/**
	 * Define all the type definitions from the queue.
	 */
	public static function run (): Void {
		
		var usings:Array<TypePath> = [];
		var c:ClassType;
		
		var tp:TypePath;
		var moduleName:String;
		for (cref in Context.getLocalUsing()) {
			
			c = cref.get();
			
			switch (c.kind) {
				case ClassKind.KNormal | ClassKind.KGeneric | ClassKind.KGenericBuild:
					
					moduleName = c.module.substr(c.module.lastIndexOf(".") + 1);
					
					if (moduleName == c.name) {
						tp = {
							name:c.name,
							pack:c.pack.copy()
						};
					} else {
						tp = {
							name:moduleName,
							pack:c.pack,
							sub:c.name
						};
					}
					
					usings.push(tp);
					
				default:
			}
		}
		
		var imports:Array<ImportExpr> = Context.getLocalImports();
		
		Context.defineModule(Context.getLocalClass().get().module, typeDefinitionStack, imports, usings);
		
		typeDefinitionStack = new Array<TypeDefinition>();
	}
	
	private static function addProperty (bd:BuildingData, name:String, access:Array<Access>, type:ComplexType, pos:Position): Void {
		
		bd.typeDefinition.fields.push({
			name:   name,
			access: access,
			kind:   FVar( type, null ),
			pos:    pos,
			doc:    null,
			meta:   null
		});
	}
	
	private static function addMethod (bd:BuildingData, name:String, access:Array<Access>, args:Array<FunctionArg>, ret:ComplexType, expr:Expr, pos:Position, metadata:Null<Metadata> = null): Void {
		
		var fn:Function = {
			args:   args,
			ret:    ret,
			expr:   expr,
			params: null
		}
		
		bd.typeDefinition.fields.push({
			name:   name,
			doc:    null,
			access: access,
			kind:   FFun( fn ),
			pos:    pos,
			meta:   metadata
		});
	}
	
	private static function addMeta (bd:BuildingData, name:String, ?params:Array<Expr>, pos:Position): Void {
		
		bd.typeDefinition.meta.push({
			name:   name,
			params: params,
			pos:    pos
		});
	}
	
	private static function initParentDependencies (bd:BuildingData, workEnv:WorkEnv, pos:Position): Void {
		
		for (dependence in workEnv.parentDependencies) {
			
			// Add the argument of the parent as a field
			
			var dependenceName:String = NameController.fieldParent(workEnv, dependence);
			
			addProperty(bd, dependenceName, [APrivate], dependence.getGeneratedComplexType(), pos);
			
			var constructorArgName:String = NameController.argParent(workEnv, dependence);
			
			bd.constructorArgs.push({
				name:  constructorArgName, 
				opt:   false, 
				type:  dependence.getGeneratedComplexType(),
				value: null, 
				meta:  null
			});
			
			bd.constructorBlock.push(macro $i{dependenceName} = $i{constructorArgName});
			
			// Pass the parent through arguments
			
			if (dependence == workEnv.parent) {
				bd.givenArguments.push({
					expr: EConst(CIdent("this")),
					pos:  pos
				});
			} else {
				bd.givenArguments.push({
					expr: EField( {expr: EConst(CIdent("this")), pos: pos}, dependenceName),
					pos:  pos
				});
			}
			
		}
	}
	
	private static function initParentAsVarDependencies (bd:BuildingData, workEnv:WorkEnv, pos:Position): Void {
		
		for (dependence in workEnv.parentAsVarDependencies) {
			
			// Add the local variable as a field
			
			var ic:IdentChannel = switch (dependence.identData.identType)  {
				case IdentType.Accession(_ic, _definition): _ic;
				default: throw "irrelevant ident type : " + dependence.identData.identType;
			};
			
			var fieldName:String = NameController.parentVar(dependence.identData.names[0], dependence.identData.scope, ic, dependence.env.getParentCount());
			
			addProperty(bd, fieldName, [APrivate], dependence.identData.types[0], pos);
			
			var constructorArgName:String = NameController.argParentAsVar(fieldName);
			
			bd.constructorArgs.push({
				name:  constructorArgName, 
				opt:   false, 
				type:  dependence.identData.types[0],
				value: null, 
				meta:  null
			});
			
			bd.constructorBlock.push(macro $i{fieldName} = $i{constructorArgName});
			
			// Pass the local variable through arguments
			
			if (dependence.env == workEnv.parent) {
				
				var econst:Expr = switch (dependence.identData.ident) {
					case IdentRef.IEConst(eRef): { expr: eRef.expr, pos: eRef.pos };
					default: null;
				}
				
				bd.givenArguments.push(econst);
				
				dependence.env.addLocalAccession(dependence.identData.names[0], dependence.identData.initialized[0], dependence.identData.types[0], IdentRef.IEConst(econst), ic, econst.pos);
				
			} else {
				bd.givenArguments.push({
					expr: EField( {expr: EConst(CIdent("this")), pos: pos}, fieldName),
					pos: pos
				});
			}
		}
	}
	
	private static function initInstanceDependency (bd:BuildingData, workEnv:WorkEnv, pos:Position): Void {
		
		// instance of the class
		
		if (workEnv.requiresInstance) {
			
			// Add the argument of the instance as a field
			
			var lInstanceCT:ComplexType = !workEnv.isAbstract ? workEnv.classComplexType : TypeTools.toComplexType(workEnv.abstractType.type);
			
			addProperty(bd, NameController.fieldInstance(), [APrivate], lInstanceCT, pos);
			
			bd.constructorArgs.push({
				name:  NameController.argInstance(), 
				opt:   false, 
				type:  lInstanceCT, 
				value: null, 
				meta:  null
			});
			
			bd.constructorBlock.push(macro $i{NameController.fieldInstance()} = $i{NameController.argInstance()});
			
			// Pass the instance through arguments
			
			if (workEnv.parent != null) {
				
				var lexpr:Expr = { expr: EConst(CIdent("this")), pos: pos };
				
				workEnv.parent.addInstanceAccession(null, workEnv.parent.getGeneratedComplexType(), IdentRef.IEConst(lexpr), IdentChannel.Normal, lexpr.pos);
				
				bd.givenArguments.push(lexpr);
				
			} else {
				
				if (workEnv.parent == null) {
					
					bd.givenArguments.push({
						expr: EConst(CIdent("this")),
						pos:  pos
					});
					
				} else {
					
					bd.givenArguments.push({
						expr: EField( {expr: EConst(CIdent("this")), pos: pos}, NameController.fieldInstance()),
						pos:  pos
					});
				}
			}
		}
	}
	
	private static function initIteratorInitialisations (bd:BuildingData, workEnv:WorkEnv, ibd:IteratorBlockData, pos:Position): Void {
		
		var nextMethodType:ComplexType = ComplexType.TFunction([macro:Void], workEnv.returnType);
		
		addProperty(bd, NameController.fieldStack(), [APrivate], macro:Array<$nextMethodType>, pos);
		addProperty(bd, NameController.fieldCursor(), [APrivate], macro:StdTypes.Int, pos);
		addProperty(bd, NameController.fieldCurrent(), [APrivate], workEnv.returnType, pos);
		addProperty(bd, NameController.fieldIsConsumed(), [APrivate], macro:StdTypes.Bool, pos); 
		addProperty(bd, NameController.fieldCompleted(), [APrivate], macro:StdTypes.Bool, pos); 
		
		// Initialize arguments
		
		for (argData in workEnv.functionArguments) {
			
			var newArgName:String = NameController.argArgument(argData.originalArg);
			var constructorArg:FunctionArg;
			
			// in extra-type constructor
			
			bd.constructorArgs.push({
				name:  newArgName,
				meta:  argData.originalArg.meta,
				opt:   false,
				type:  argData.originalArg.type,
				value: null
			});
			
			switch (argData.definition.ident) {
				case IdentRef.IEVars(eRef):
					
					switch (eRef.expr) {
						case EVars(_vars):
							for (v in _vars) v.expr = { expr: EConst(CIdent( newArgName )), pos: v.expr.pos };
							bd.constructorBlock.push(eRef);
						default:
					}
					
				default: throw "irrelevant ident reference : " + argData.definition.ident;
			}
			
			// in new call
			
			if (workEnv.parent != null) {
				argData.originalArg.name = newArgName; // modify the name of the original argument as arg-name to avoid collisions with potential operative variables
			}
			
			bd.givenArguments.push({ expr:EConst(CIdent(argData.originalArg.name)), pos:argData.definition.pos });
		}
		
		// Initialize properties
		
		var exprs = [];
		
		for (i in 0...ibd.length) {
			exprs.push({expr:EConst(CIdent( NameController.iterativeFunction(i) )), pos:pos});
		}
		
		bd.constructorBlock.push(macro $i{NameController.fieldCursor()}	 = -1);
		bd.constructorBlock.push(macro $i{NameController.fieldStack()}	  = $a{exprs});
		
		bd.constructorBlock.push(macro $i{NameController.fieldCurrent()}	= $e{workEnv.defaultReturnType});
		bd.constructorBlock.push(macro $i{NameController.fieldIsConsumed()} = true);
		bd.constructorBlock.push(macro $i{NameController.fieldCompleted()}  = false);
	}
	
	private static function initIteratorMethods (bd:BuildingData, workEnv:WorkEnv, ibd:IteratorBlockData, pos:Position): Void {
		
		// public function hasNext():Bool
		
		var body:Expr = {
			expr: EBlock([
			  macro if (!$i{NameController.fieldIsConsumed()}) return true;
					else if ($i{NameController.fieldCursor()} < $v{bd.lastSequence}) {
						$i{NameController.fieldCurrent()} = $i{NameController.fieldStack()}[++$i{NameController.fieldCursor()}]();
						if (!$i{NameController.fieldCompleted()}) { $i{NameController.fieldIsConsumed()} = false; return true; }
						else return false;
					},
			  macro return false
			]), 
			pos: pos
		};
		
		addMethod(bd, "hasNext", [APublic], [], macro:StdTypes.Bool, body, pos);
		
		// public function next():???
		
		var body:Expr = {
			expr: EBlock([
				macro if ($i{NameController.fieldIsConsumed()} && !hasNext()) { return $e{workEnv.defaultReturnType}; },
				macro $i{NameController.fieldIsConsumed()} = true,
				macro return $i{NameController.fieldCurrent()}
			]), 
			pos: pos
		};
		
		addMethod(bd, "next", [APublic], [], workEnv.returnType, body, pos);
		
		// public inline function iterator():Iterator<???>
		
		switch (workEnv.functionRetType) {
			case ITERABLE | DYNAMIC:
				
				var body:Expr = {
					expr: EBlock([
						macro return this
					]), 
					pos: pos
				};
				
				var rtype:ComplexType = workEnv.returnType;
				var metadata:Metadata = null;
				
				if (workEnv.functionRetType == RetType.DYNAMIC) {
					metadata = [{
						name: ":keep",
						params: null,
						pos:    pos
					}];
				}
				
				addMethod(bd, "iterator", [APublic, AInline], [], macro:StdTypes.Iterator<$rtype>, body, pos, metadata);
				
			case ITERATOR:
		}
	}
	
	private static function initConstructor (bd:BuildingData, pos:Position): Void {
		
		var body:Expr = { expr: EBlock(bd.constructorBlock), pos: pos };
		addMethod(bd, "new", [APublic], bd.constructorArgs, null, body, pos);
	}
	
	private static function initTypeMetas (bd:BuildingData, pos:Position): Void {
		
		addMeta(bd, ":noDoc", null, pos);
		addMeta(bd, ":final", null, pos);
	}
	
	private static function initTypeParams (bd:BuildingData, workEnv:WorkEnv, pos:Position): Void {
		
		bd.typeDefinition.params = [];
		var ids:Array<String>    = [];
		
		function addTypeParameters (params:Array<TypeParameter>): Void {
			
			for (param in params) {
				
				if (ids.indexOf(param.name) != -1) continue;
				
				var p:TypeParamDecl = ExpressionTools.convertToTypeParamDecl(param.t, param.name);
				
				bd.typeDefinition.params.push(p);
				ids.push(p.name);
			}
		}
		
		// Add params from the Class and Function
		
		if (workEnv.isAbstract) {
			addTypeParameters(workEnv.abstractType.params);
		}
		
		addTypeParameters(workEnv.classType.params);
		
		for (param in workEnv.classFunction.params) {
			
			if (ids.indexOf(param.name) != -1) continue;
			
			var p:TypeParamDecl = {
				constraints: param.constraints,
				meta:        param.meta,
				name:        param.name,
				params:      param.params
			};
			
			bd.typeDefinition.params.push(p);
			ids.push(p.name);
		}
	}
	
	private static function initIteratorActions (bd:BuildingData, workEnv:WorkEnv, pos:Position): Void {
		
		for (aGoto in workEnv.gotoActions) {
			
			var lset:Expr = { expr: null, pos: aGoto.e.pos};
			
			workEnv.setActions.push({ e: lset, pos: aGoto.pos + 1 });
			
			var call:Expr = ExpressionTools.makeCall("_" + (aGoto.pos) + "_", [], aGoto.e.pos);
			
			aGoto.e.expr = EBlock([
				lset,
				{ expr: EReturn(call), pos: aGoto.e.pos }
			]);
		}
		
		for (aSetNext in workEnv.setActions) {
			
			aSetNext.e.expr = EBinop(
				Binop.OpAssign, 
				{ expr: EField({ expr: EConst(CIdent("this")), pos: pos }, NameController.fieldCursor()), pos: aSetNext.e.pos },
				{ expr: EConst(CInt( Std.string(aSetNext.pos - 1) )), pos: aSetNext.e.pos }
			);
		}
		
		for (aBreak in workEnv.breakActions) {
			
			aBreak.e.expr = EBlock([
				macro $i{NameController.fieldCompleted()} = true,
				macro return ${workEnv.defaultReturnType}
			]);
		}
	}
	
	private static function initInstanceAccessions (workEnv:WorkEnv): Void {
		
		// Transform instance accessions
		
		for (identData in workEnv.instanceIdentStack) {
			
			switch (identData.ident) {
				case IdentRef.IEConst(eRef):
					
					if (identData.names == null) {
						eRef.expr = EField( {expr: EConst(CIdent('this')), pos: eRef.pos}, NameController.fieldInstance() );
					} else {
						eRef.expr = EField({
							expr: EField( {expr: EConst(CIdent('this')), pos: eRef.pos}, NameController.fieldInstance() ),
							pos : eRef.pos
						}, identData.names[0]);
					}
					
				default: throw "irrelevant ident reference : " + identData.ident;
			}
		}
	}
	
	private static function initParentAccessions (workEnv:WorkEnv): Void {
		
		// Transform parent accessions
		
		for (identData in workEnv.parentIdentStack) {
			
			if (identData.option != IdentOption.KeepAsVar) {
				
				var parentFieldName:String = NameController.fieldParent(workEnv, identData.parent);
				
				switch (identData.ident) {
					case IdentRef.IEConst(eRef):
						
						if (identData.names[0] == null) {
							eRef.expr = EField( {expr: EConst(CIdent('this')), pos: eRef.pos}, parentFieldName );
						} else {
							
							var lfield:Expr = {
								expr: EField({
									expr: EField( {expr: EConst(CIdent('this')), pos: eRef.pos}, parentFieldName ),
									pos : eRef.pos
								}, identData.names[0] ),
								pos: eRef.pos
							};
							
							eRef.expr = lfield.expr;
						}
						
					default: throw "irrelevant ident reference : " + identData.ident;
				}
				
			} else {
				
				var ic:IdentChannel;
				var definition:IdentData;
				
				switch (identData.identType)  {
					case IdentType.Accession(_ic, _definition): 
						ic = _ic;
						definition = _definition;
					default: throw "irrelevant ident type : " + identData.identType;
				};
				
				var parentFieldName:String = NameController.parentVar(identData.names[0], identData.scope, ic, definition.env.getParentCount());
				
				// rename accession
				
				switch (identData.ident) {
					case IdentRef.IEConst(eRef):
						eRef.expr = EField({ expr: EConst(CIdent("this")), pos: eRef.pos }, parentFieldName);
						
						eRef.expr = EConst(CIdent(parentFieldName));
					default: throw "irrelevant ident reference : " + identData.ident;
				}
			}
		}
	}
	
	private static function initVariableFields (bd:BuildingData, workEnv:WorkEnv): Void {
		
		// Prepare ident channels
		
		var newNameChannels:Map<IdentChannel, Map<UInt, Map<String, String>>> = new Map<IdentChannel, Map<UInt, Map<String, String>>>();
		var nameCounterChannels:Map<IdentChannel, Map<UInt, Map<String, UInt>>> = new Map<IdentChannel, Map<UInt, Map<String, UInt>>>();
		
		for (ic in IdentChannel.getConstructors()) {
			newNameChannels.set(IdentChannel.createByName(ic), new Map<UInt, Map<String, String>>());
			nameCounterChannels.set(IdentChannel.createByName(ic), new Map<UInt, Map<String, UInt>>());
		}
		
		// Process transformations
		
		var newNames:Map<String, String>;
		var nameCounter:Map<String, UInt>;
		
		for (identData in workEnv.localIdentStack) {
			
			switch (identData.identType) {
				
				case IdentType.Accession(_ic, _definition):
					
					if (_definition == null) {
						Context.fatalError("Unknown identifier : " + identData.names[0], identData.pos);
					}
					
					var scopeDefenition:Scope;
					
					if (newNameChannels[_ic].exists(_definition.scope.id)) {
						scopeDefenition = _definition.scope;
					} else {
						Context.fatalError("Unknown identifier : " + identData.names[0], identData.pos);
					}
					
					newNames    = newNameChannels[_ic][scopeDefenition.id];
					nameCounter = nameCounterChannels[_ic][scopeDefenition.id];
					
					// Change the accession
					
					switch (identData.ident) {
						
						case IdentRef.IEConst(eRef) | IdentRef.IEField(eRef):
							
							switch (eRef.expr) {
								
								case EConst(_c):
									
									if (_definition.option != IdentOption.KeepAsVar) {
										eRef.expr = EField({ expr: EConst(CIdent("this")), pos: eRef.pos }, newNames[identData.names[0]]);
									} else {
										eRef.expr = EConst(CIdent(newNames[identData.names[0]]));
									}
									
								case EField(_e, _field):
									
									eRef.expr = EField(_e, newNames[identData.names[0]]);
									
								default: throw "accession not supported : " + eRef.expr;
							}
							
						default: throw "irrelevant ident reference : " + identData.ident;
					}
					
				case IdentType.Definition(ic):
					
					if (!newNameChannels[ic].exists(identData.scope.id)) {
						newNameChannels[ic].set( identData.scope.id, new Map<String, String>() );
						nameCounterChannels[ic].set( identData.scope.id, new Map<String, UInt>() );
					}
					
					newNames    = newNameChannels[ic][identData.scope.id];
					nameCounter = nameCounterChannels[ic][identData.scope.id];
					
					if (identData.names[0] == null) continue;
					
					// Define the new identifier
					
					var counter:UInt;
					for (i in 0...identData.names.length) {
						
						if (!nameCounter.exists(identData.names[i])) counter = 0;
						else counter = nameCounter[identData.names[i]];
						
						var newNameRc:String;
						do {
							newNameRc = NameController.localVar(identData.names[i], identData.scope, ic, ++counter);
						} while (workEnv.getIdentCategoryOf(newNameRc) != IdentCategory.Unknown);
						
						nameCounter.set( identData.names[i], counter );
						newNames.set( identData.names[i], newNameRc );
					}
					
					// Change the declaration
					
					switch (identData.ident) {
						
						case IdentRef.IEVars(eRef): switch (eRef.expr) {
							case EVars(_vars):
								
								var varCount:Int = _vars.length;
								
								for (i in 0...varCount) {
									
									var __var = _vars[i];
									
									if (__var.name == identData.names[i]) {
										
										__var.name = newNames[identData.names[i]];
										
										// add local variable as field
										
										if (identData.option != IdentOption.KeepAsVar) {
											
											var lfieldDecl:Field;
											
											if (WorkEnv.isDynamicTarget())
												if (__var.type == null)
													lfieldDecl = FieldTools.makeFieldFromVar(__var, [APublic], {expr:EConst(CIdent("null")), pos: eRef.pos}, eRef.pos);
												else 
													lfieldDecl = FieldTools.makeFieldFromVar(__var, [APublic], null, eRef.pos);
											else
												lfieldDecl = FieldTools.makeFieldFromVar(__var, [APublic], null, eRef.pos);
											
											lfieldDecl.name = newNames[identData.names[i]];
											bd.typeDefinition.fields.push( lfieldDecl );
										}
									}
								}
								
								// transform var declaration into field assignment
								
								if (identData.option != IdentOption.KeepAsVar) {
									
									var assignations:Array<Expr> = [];
									
									var i:Int = varCount;
									while (--i != -1) {
										
										if (_vars[i].expr != null)
											assignations.push( FieldTools.makeFieldAssignation(newNames[identData.names[i]], _vars[i].expr) );
										else
											_vars.splice(i, 1);
									}
									
									if (assignations.length == 1) 
										eRef.expr = assignations[0].expr;
									else 
										eRef.expr = EBlock(assignations);
									
								}
								
							default:
						}
						case IdentRef.IEFunction(eRef): switch (eRef.expr) {
							case EFunction(_name, _f):
								
								if (identData.option != IdentOption.KeepAsVar) {
									
									// add local function as field
									var lfieldDecl:Field = FieldTools.makeField(newNames[identData.names[0]], [APublic], {expr:EConst(CIdent("null")), pos: eRef.pos}, eRef.pos);
									bd.typeDefinition.fields.push( lfieldDecl );
									
									// transform function declaration into field assignment
									eRef.expr = FieldTools.makeFieldAssignation(newNames[identData.names[0]], {expr:EFunction(null, _f), pos: eRef.pos}).expr;
									
								} else {
									
									eRef.expr = EFunction(newNames[identData.names[0]], _f);
								}
								
							default:
						}
						case IdentRef.IEConst(eRef): switch (eRef.expr) {
							case EConst(_c):
								eRef.expr = EConst(CIdent(newNames[identData.names[0]]));
								
							default:
						}
						
						case IdentRef.ICatch(cRef):
							cRef.name = newNames[identData.names[0]];
							
						case IdentRef.IArg(aRef, pos):
							aRef.name = newNames[identData.names[0]];
							
						default: throw "irrelevant ident reference : " + identData.ident;
					}
			}
			
		}
	}
	
	private static function initIterativeFunctions (bd:BuildingData, workEnv:WorkEnv, ibd:IteratorBlockData): Void {
		
		for (i in 0...ibd.length) {
			
			var lExpressions:Array<Expr> = ibd[i];
			
			var body:Expr = { expr: EBlock(lExpressions), pos: lExpressions[0].pos };
			
			addMethod(bd, NameController.iterativeFunction(i), [APrivate], [], workEnv.returnType, body, lExpressions[0].pos, workEnv.classField.meta.copy());
		}
	}
	
	private static function initInstanceFunctionBody (bd:BuildingData, pos:Position): Void {
		
		var enew:Expr = {
			expr: ENew(bd.typePath, bd.givenArguments),
			pos:  pos
		};
		
		var ereturn:Expr = {
			expr: EReturn(enew),
			pos:  pos
		};
		
		bd.instanceFunctionBody = {
			expr: EBlock([ereturn]),
			pos:  pos
		};
	}
	
	static function getTypePath (c:Type, isAbstract:Bool = false, abstractType:AbstractType = null): String {
		
		var classPackage:String;
		
		switch (TypeTools.toComplexType(c)) {
			case TPath(tp):
				
				classPackage = "";
				
				var pack = tp.pack;
				var name = tp.name;
				
				if (isAbstract) {
					pack = abstractType.pack;
					name = abstractType.name;
				}
				
				if (pack.length != 0) classPackage += pack.join(".") + ".";
				
				if (tp.sub != null) {
					classPackage += name + "." + tp.sub;
				} else {
					classPackage += name;
				}
				
			default:
				throw "type not supported : " + ComplexTypeTools.toString(TypeTools.toComplexType(c));
		}
		
		return classPackage;
	}
	
	private static function allowAccessToPrivateFields (workEnv:WorkEnv, pos:Position): Void {
		
		if (workEnv.classComplexType != null) {
			
			workEnv.generatedIteratorClass.meta.push({
				name : ":access",
				params : [Context.parse(getTypePath(Context.getLocalType(), workEnv.isAbstract, workEnv.abstractType), pos)],
				pos : pos
			});
			
			if (workEnv.isAbstract) {
				
				workEnv.generatedIteratorClass.meta.push({
					name : ":access",
					params : [Context.parse(getTypePath(workEnv.abstractType.type), pos)],
					pos : pos
				});
			}
		}
	}
	
}
#end