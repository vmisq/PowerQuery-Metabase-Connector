[Version = "1.0.0"]
section Metabase;

[DataSource.Kind="Metabase", Publish="Metabase.Publish"]
shared Metabase.Contents = (metabase_url as text) =>
    let
        session_token = Metabase.Auth(metabase_url),
        table_data = Metabase.GetTables(metabase_url, session_token),
        table_nav = Metabase.TableNav(table_data),
        card_data = Metabase.GetCards(metabase_url, session_token),
        card_nav = Metabase.CardNav(card_data),
        navTable = Table.ToNavigationTable(Table.Combine({table_nav, card_nav}), {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        navTable;

// Data Source Kind description
Metabase = [
    TestConnection = (dataSourcePath) => {"Metabase.Contents", Json.Document(dataSourcePath)[metabase_url]},
    // Disconnect = (dataSourcePath) => {"Metabase.Logout", Json.Document(dataSourcePath)[metabase_url]},
    Authentication = [
        UsernamePassword = [],
        Key = [Label = "Session Token"]
    ],
    Label = "Metabase"
];

// Data Source UI publishing description
Metabase.Publish = [
    Beta = true,
    Category = "Database",
    ButtonText = {"Metabase", Extension.LoadString("FormulaHelp")},
    SourceImage = Metabase.Icons,
    SourceTypeImage = Metabase.Icons
];

Metabase.Icons = [
    Icon16 = { Extension.Contents("Metabase16.png"), Extension.Contents("Metabase20.png"), Extension.Contents("Metabase24.png"), Extension.Contents("Metabase32.png") },
    Icon32 = { Extension.Contents("Metabase32.png"), Extension.Contents("Metabase40.png"), Extension.Contents("Metabase48.png"), Extension.Contents("Metabase64.png") }
];


// Data Source Auth
Metabase.Auth = (metabase_url as text) =>
    let
        session_token = if Extension.CurrentCredential()[AuthenticationKind] = "Key" then Extension.CurrentCredential()[Key] else UsernamePasswordAuth(metabase_url)
    in
        session_token;

UsernamePasswordAuth = (metabase_url as text) =>
    let
        username = Extension.CurrentCredential()[Username],
        password = Extension.CurrentCredential()[Password],

        auth_payload = Text.ToBinary("{""username"": """ & username & """, ""password"": """ & password & """}"),
        auth_headers = [
            #"Content-Type" = "application/json"
        ],
        response = Web.Contents(
            metabase_url,
            [
                Headers = auth_headers,
                Content = auth_payload,
                RelativePath = "/api/session",
                ManualStatusHandling = {400, 401, 403, 404, 500} // Handle error responses as needed
            ]
        ),
        session_token = Json.Document(Text.FromBinary(response))[id]
    in
        session_token;

// Data Source Logic Functions
Metabase.GetCollections = (metabase_url as text, session_token as text) =>
    let
        headers = [
            #"Content-Type" = "application/json",
            #"X-Metabase-Session" = session_token
        ],
        response = Web.Contents(
            metabase_url,
            [
                Headers = headers,
                RelativePath = "/api/collection",
                ManualStatusHandling = {400, 401, 403, 404, 500} // Handle error responses as needed
            ]
        ),
        content = Json.Document(Text.FromBinary(response)),
        content_collection = Table.FromList(content, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        content_collection_all = Table.ExpandRecordColumn(content_collection, "Column1", {"name", "id", "location"}, {"Name", "id", "location"}),
        
        content_collection_all_type = Table.TransformColumnTypes(content_collection_all,{{"id", type text}, {"location", type text}, {"Name", type text}}),
        content_collection_all_replace = Table.ReplaceValue(content_collection_all_type,null,"",Replacer.ReplaceValue,{"location"}),
        content_collection_all_helper = Table.AddColumn(content_collection_all_replace, "helper_id", each "/" & [id] & "/", type text),
        content_collection_all_helper_loc = Table.AddColumn(content_collection_all_helper, "helper_location", each "/root" & [location], type text),
        content_collection_all_path_ref = Table.AddColumn(content_collection_all_helper_loc, "PathRef", each Json.Document("{""Name"": ""/" & [Name] & "/"", ""helper_id"": """ & [helper_id] & """}")),
        PathRef = content_collection_all_path_ref[PathRef],
        RecursiveReplace = (table_to_replace, cur_val) =>
            let
                nextReplace = Table.ReplaceValue(table_to_replace, PathRef{cur_val}[helper_id], PathRef{cur_val}[Name], Replacer.ReplaceText, {"helper_location"}),
                result = if cur_val = List.Count(PathRef) - 1 then nextReplace else @RecursiveReplace(nextReplace, cur_val + 1)
            in
                result,
        content_collection_all_replaced = RecursiveReplace(content_collection_all_path_ref, 0),
        content_collection_path = Table.AddColumn(content_collection_all_replaced, "collection_path", each if [helper_location] = "/root" then [Name] else Text.AfterDelimiter([helper_location], "/") & [Name]),
        content_collection_path_replaced = Table.ReplaceValue(content_collection_path,"/"," / ",Replacer.ReplaceText,{"collection_path"}),
        
        content_collection_done = Table.SelectColumns(content_collection_path_replaced,{"id", "collection_path"})
    in
        content_collection_done;

Metabase.Card = (metabase_url as text, card_id as text, session_token as text) =>
    let
        headers = [
            #"Content-Type" = "application/json",
            #"X-Metabase-Session" = session_token
        ],
        response = Web.Contents(
            metabase_url,
            [
                Headers = headers,
                RelativePath = "/api/card/" & card_id & "/query/csv",
                Content = Text.ToBinary("{}"),
                ManualStatusHandling = {400, 401, 403, 404, 500} // Handle error responses as needed
            ]
        ),
        content = Csv.Document(Text.FromBinary(response)),
        data_table = Table.PromoteHeaders(content, [PromoteAllScalars=true])
    in
        data_table;

Metabase.GetCards = (metabase_url as text, session_token as text) =>
    let
        headers = [
            #"Content-Type" = "application/json",
            #"X-Metabase-Session" = session_token
        ],
        response = Web.Contents(
            metabase_url,
            [
                Headers = headers,
                RelativePath = "/api/card",
                ManualStatusHandling = {400, 401, 403, 404, 500} // Handle error responses as needed
            ]
        ),
        content = Json.Document(Text.FromBinary(response)),
        content_card = Table.FromList(content, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        content_card_id = Table.ExpandRecordColumn(content_card, "Column1", {"name", "id", "collection_id", "database_id"}, {"Name", "id", "collection_id", "db_id"}),
        content_card_id_text = Table.TransformColumnTypes(content_card_id,{{"id", type text}, {"collection_id", type text}, {"db_id", type text}}),
        content_card_id_replaced = Table.ReplaceValue(content_card_id_text,null,"root",Replacer.ReplaceValue,{"collection_id"}),
        content_card_data = Table.AddColumn(content_card_id_replaced, "Data", each Metabase.View(metabase_url, _[db_id], "card__" & _[id], session_token)),
        content_card_item_kind = Table.AddColumn(content_card_data, "ItemKind", each "View"),
        content_card_item_name = Table.AddColumn(content_card_item_kind, "ItemName", each "Table"),
        content_card_is_leaf = Table.AddColumn(content_card_item_name, "IsLeaf", each true),
        content_card_all = Table.SelectColumns(content_card_is_leaf, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf", "collection_id"}),
        collection_table = Metabase.GetCollections(metabase_url, session_token),
        merged_table = Table.NestedJoin(content_card_all, {"collection_id"}, collection_table, {"id"}, "CollectionTable", JoinKind.LeftOuter),
        content_card_done = Table.ExpandTableColumn(merged_table, "CollectionTable", {"collection_path"}, {"collection_path"})
    in
        content_card_done;

Metabase.CardNav = (content_card_done as table) =>
    let
        content_card_format = Table.SelectColumns(content_card_done, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf", "collection_path"}),
        content_card_base = Table.AddColumn(content_card_format, "base", each "Questions"),
        groupby_card = Table.Group(content_card_base, {"base", "collection_path"}, {{"Data", each Table.ToNavigationTable(Table.SelectColumns(_, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}), {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")}}),
        groupby_card_add_kind = Table.AddColumn(groupby_card, "ItemKind", each "Folder"),
        groupby_card_add_name = Table.AddColumn(groupby_card_add_kind, "ItemName", each "Table"),
        groupby_card_add_leaf = Table.AddColumn(groupby_card_add_name, "IsLeaf", each false),

        card_collection_table = Table.RenameColumns(groupby_card_add_leaf,{{"collection_path", "Name"}}),
        card_collection_groupdb = Table.Group(card_collection_table, {"base"}, {{"Data", each Table.ToNavigationTable(Table.SelectColumns(_, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}), {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")}}),
        card_collection_rename = Table.RenameColumns(card_collection_groupdb,{{"base", "Name"}}),
        card_collection_groupby_db_add_kind = Table.AddColumn(card_collection_rename, "ItemKind", each "Folder"),
        card_collection_groupby_db_add_name = Table.AddColumn(card_collection_groupby_db_add_kind, "ItemName", each "Table"),
        card_collection_groupby_db_add_leaf = Table.AddColumn(card_collection_groupby_db_add_name, "IsLeaf", each false),
        
        card_final = Table.Group(card_collection_groupby_db_add_leaf, {"Name"}, {{"Data", each Table.Combine([Data]), type table [Name=text, Data=table, ItemKind=text, ItemName=text, IsLeaf=logical]}, {"ItemKind", each List.Min([ItemKind]), type text}, {"ItemName", each List.Min([ItemName]), type text}, {"IsLeaf", each List.Min([IsLeaf]), type logical}})
    in
        card_final;

Metabase.GetData = (metabase_url as text, database_id as text, table_id as text, session_token as text, optional state as record) =>
    let
        headers = [
            #"Content-Type" = "application/x-www-form-urlencoded",
            #"X-Metabase-Session" = session_token
        ],
        query_folding = if state[Top]? = null then "" else ", ""limit"": " & Number.ToText(state[Top]),
        table_or_card_id = if Text.StartsWith(table_id, "card__") then """" & table_id & """" else table_id,
        query = "{""database"": " & database_id &", ""type"": ""query"", ""query"": {""source-table"": " & table_or_card_id  & query_folding & "}}",
        request_body = Text.ToBinary("query=" & query),
        response = Web.Contents(
            metabase_url,
            [
                Headers = headers,
                RelativePath = "/api/dataset/csv",
                Content = request_body,
                ManualStatusHandling = {400, 401, 403, 404, 500} // Handle error responses as needed
            ]
        ),
        content = Csv.Document(Text.FromBinary(response)),
        data_table = Table.PromoteHeaders(content, [PromoteAllScalars=true])
    in
        data_table;

Metabase.TableRows = (metabase_url as text, database_id as text, table_id as text, session_token as text) =>
    let
        headers = [
            #"Content-Type" = "application/x-www-form-urlencoded",
            #"X-Metabase-Session" = session_token
        ],
        query = "{""database"": " & database_id &", ""type"": ""query"", ""query"": {""source-table"": " & table_id & ", ""aggregation"":[[""count"",null]]}}}",
        request_body = Text.ToBinary("query=" & query),
        response = Web.Contents(
            metabase_url,
            [
                Headers = headers,
                RelativePath = "/api/dataset/csv",
                Content = request_body,
                ManualStatusHandling = {400, 401, 403, 404, 500} // Handle error responses as needed
            ]
        ),
        content = Csv.Document(Text.FromBinary(response)),
        data_table = Table.PromoteHeaders(content, [PromoteAllScalars=true]),
        nrows = data_table[Count]{0}
    in
        nrows;

Metabase.GetTables = (metabase_url as text, session_token as text) =>
    let
        headers = [
            #"Content-Type" = "application/json",
            #"X-Metabase-Session" = session_token
        ],
        response = Web.Contents(
            metabase_url,
            [
                Headers = headers,
                RelativePath = "/api/table",
                ManualStatusHandling = {400, 401, 403, 404, 500} // Handle error responses as needed
            ]
        ),
        content = Json.Document(Text.FromBinary(response)),
        content_table = Table.FromList(content, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        content_table_id = Table.ExpandRecordColumn(content_table, "Column1", {"display_name", "id", "db_id", "schema", "db"}, {"Name", "id", "db_id", "schema_name", "db"}),
        content_table_id_db_name = Table.ExpandRecordColumn(content_table_id, "db", {"name"}, {"db_name"}),
        content_table_id_text = Table.TransformColumnTypes(content_table_id_db_name,{{"id", type text}, {"db_id", type text}}),
        content_table_data = Table.AddColumn(content_table_id_text, "Data", each Metabase.View(metabase_url, _[db_id], _[id], session_token)),
        content_table_item_kind = Table.AddColumn(content_table_data, "ItemKind", each "Table"),
        content_table_item_name = Table.AddColumn(content_table_item_kind, "ItemName", each "Table"),
        content_table_is_leaf = Table.AddColumn(content_table_item_name, "IsLeaf", each true),
        content_table_done = Table.SelectColumns(content_table_is_leaf, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf", "db_name", "schema_name"})
    in
        content_table_done;
    
Metabase.TableNav = (content_table_done as table) =>
    let
        groupby_db = Table.Group(content_table_done, {"db_name", "schema_name"}, {{"Data", each Table.ToNavigationTable(Table.SelectColumns(_, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}), {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")}}),
        groupby_db_add_kind = Table.AddColumn(groupby_db, "ItemKind", each "Database"),
        groupby_db_add_name = Table.AddColumn(groupby_db_add_kind, "ItemName", each "Table"),
        groupby_db_add_leaf = Table.AddColumn(groupby_db_add_name, "IsLeaf", each false),

        db_only = Table.SelectRows(groupby_db_add_leaf, each ([schema_name] = null or [schema_name] = "")),
        db_only_table = Table.RenameColumns(db_only,{{"db_name", "Name"}}),
        db_only_table_done = Table.SelectColumns(db_only_table, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}),

        db_schema = Table.SelectRows(groupby_db_add_leaf, each ([schema_name] <> null and [schema_name] <> "")),
        db_schema_table = Table.RenameColumns(db_schema,{{"schema_name", "Name"}}),
        db_schema_groupdb = Table.Group(db_schema_table, {"db_name"}, {{"Data", each Table.ToNavigationTable(Table.SelectColumns(_, {"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}), {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")}}),
        db_schema_rename = Table.RenameColumns(db_schema_groupdb,{{"db_name", "Name"}}),
        db_schema_groupby_db_add_kind = Table.AddColumn(db_schema_rename, "ItemKind", each "Database"),
        db_schema_groupby_db_add_name = Table.AddColumn(db_schema_groupby_db_add_kind, "ItemName", each "Table"),
        db_schema_groupby_db_add_leaf = Table.AddColumn(db_schema_groupby_db_add_name, "IsLeaf", each false),
        
        db_all = Table.Combine({db_only_table_done, db_schema_groupby_db_add_leaf}),
        db_final = Table.Group(db_all, {"Name"}, {{"Data", each Table.Combine([Data]), type table [Name=text, Data=table, ItemKind=text, ItemName=text, IsLeaf=logical]}, {"ItemKind", each List.Min([ItemKind]), type text}, {"ItemName", each List.Min([ItemName]), type text}, {"IsLeaf", each List.Min([IsLeaf]), type logical}})
    in
        db_final;

Metabase.View = (metabase_url as text, database_id as text, table_id as text, session_token as text) as table =>
    let
        View = (state as record) =>
            Table.View(
                null,
                [
                    GetType = () => Value.Type(GetRows()), // Replace for api metadata and cache it
                    GetRows = () => Metabase.GetData(metabase_url, database_id, table_id, session_token, state),
                    GetRowCount = () as number => Metabase.TableRows(metabase_url, database_id, table_id, session_token),

                    // Table.FirstN
                    OnTake = (count as number) => let newState = state & [Top = count] in @View(newState) // ,

                    // // Table.Skip
                    // OnSkip = (count as number) => let newState = state & [Skip = count] in @View(newState),
                    
                    // // Table.SelectColumns
                    // OnSelectColumns = (cols as list) => let newState = state & [Columns = cols] in @View(newState),
                    
                    // // Table.Sort
                    // OnSort = (order as list) => => let newState = state & [Order = order] in @View(newState),
                    
                    // // Cache Schema when using api schema
                    // CalculateSchema = (state) as type =>
                    //     if (state[Schema]? = null) then
                    //         Value.Type(GetRows())
                    //     else
                    //         state[Schema]
                ]
            )
    in
        View([]);

// Microsoft Navigation Table Function
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;