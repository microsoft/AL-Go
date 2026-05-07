codeunit 50100 "Test Codeunit 1"
{
    procedure TestProcedure1()
    var
        myVar: Integer;
    begin
        // This is a comment
        myVar := 10;
        if myVar > 5 then
            myVar := 20;

        DoSomething(myVar);
    end;

    procedure TestProcedure2()
    begin
        Message('Hello World');
    end;

    local procedure DoSomething(value: Integer)
    begin
        // Another comment
        Message('Value: %1', value);
    end;
}
