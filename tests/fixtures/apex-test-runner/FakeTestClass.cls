@IsTest
class FakeTestClass {
    @IsTest static void testOne() {
        System.assertEquals(1, 1);
    }
    @IsTest static void testTwo() {
        System.assertEquals(2, 2);
    }
}
