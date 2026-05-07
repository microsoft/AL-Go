page 50001 "Test Page"
{
    PageType = Card;
    SourceTable = "Test Table";

    layout
    {
        area(Content)
        {
            field(MyField; Rec.MyField)
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(MyAction)
            {
                ApplicationArea = All;
                trigger OnAction()
                begin
                    Message('Action executed');
                end;
            }
        }
    }
}
