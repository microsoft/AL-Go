page 50100 "AL File Name"
{
    PageType = List;
    SourceTable = "Sample Table";
    ApplicationArea = All;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field("ID"; "ID") { }
                field("Name"; "Name") { }
            }
        }
    }
}
