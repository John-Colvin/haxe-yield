package misc;

import utest.Assert;
import yield.Yield;

using pack.pack1.MiscFunctions;
using Lambda;

class UsingTests implements Yield
{

	public function new() {
		
	}
	
	function testSimpleUsing () {
		var it = simpleUsing("Patrick");
		
		Assert.isTrue(it.hasNext());
		Assert.equals("hello !", it.next());
		Assert.isTrue(it.hasNext());
		Assert.equals("hello Toto!", it.next());
		Assert.isTrue(it.hasNext());
		Assert.equals("hello Patrick!", it.next());
		Assert.isFalse(it.hasNext());
	}
	
	function simpleUsing (name:String): Iterator<Dynamic> {
		
		#if (neko || js || php || python || lua)
		var msg = "".sayHello();
		#else
		var msg:String = "".sayHello();
		#end
		
		@yield return msg;
		@yield return "Toto".sayHello();
		@yield return name.sayHello();
	}
	
	function testLambda () {
		Assert.equals(3, lamba().count());
		Assert.equals([0,2,4].toString(), lamba().array().toString());
	}
	
	function lamba (): Iterable<Int> {
		@yield return 0;
		@yield return 2;
		@yield return 4;
	}
	
	function testLambaAnonymous () {
		
		var result:List<String> = lamba().flatMap(function (a:Int) {
			@yield return ""+a;
			@yield return ""+a+1;
			@yield return ""+a+2;
		});
		
		var expected:List<String> = new List();
		for (i in ["0", "01", "02", "2", "21", "22", "4", "41", "42"])
			expected.add(i);
		
		Assert.equals(expected.toString(), result.toString());
	}
}

