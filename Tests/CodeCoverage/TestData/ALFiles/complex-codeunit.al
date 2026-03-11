codeunit 50102 "Complex Codeunit"
{
    // Header comments
    // More comments
    
    var
        GlobalVar: Integer;

    procedure MainProcedure(): Boolean
    var
        localVar: Text;
        counter: Integer;
    begin
        // Initialize
        localVar := 'Test';
        counter := 0;
        
        // Process
        repeat
            counter += 1;
            if counter mod 2 = 0 then
                DoEvenProcessing()
            else
                DoOddProcessing();
        until counter >= 10;
        
        exit(true);
    end;

    local procedure DoEvenProcessing()
    begin
        GlobalVar += 2;
    end;

    local procedure DoOddProcessing()
    begin
        GlobalVar += 1;
    end;

    procedure GetGlobalVar(): Integer
    begin
        exit(GlobalVar);
    end;
}
