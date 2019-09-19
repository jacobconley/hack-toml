require __DIR__.'/../../vendor/autoload.hack';

use function Facebook\FBExpect\expect;

final class DictionaryInterfaceTest extends Facebook\HackTest\HackTest {

    public function testMain() : void { 

        $x = new DictAccess(toml_decode_file(__DIR__.'/DictionaryInterfaceTest.toml'));

        expect($x->string('string'))->toBeSame('test');
        expect($x->int('int'))->toBeSame(123);
        expect($x->float('float'))->toBeSame(3.14);
        expect($x->bool('bool'))->toBeSame(true);

        $child = $x->dict('arrays');

        $intlist = $child->intlist('ints');
        expect($intlist)->toContain(1);
        expect($intlist)->toContain(2);
        expect($intlist)->toContain(5);
        expect(count($intlist))->toEqual(3);

        $dictlist = $child->dictlist('table');
        expect(count($dictlist))->toEqual(2);

        $d1 = $dictlist[0];
        $d2 = $dictlist[1];
        expect($d1->string('test1'))->toEqual('guy');
        expect($d1->int('test2'))->toEqual(69);
        expect($d2->string('test1'))->toEqual('bree');
        expect($d2->int('test2'))->toEqual(420);
    }

}
