import ballerina/encoding;
import ballerina/http;
import ballerina/lang.'int as ints;
import ballerina/regex;
import ballerinax/googleapis_sheets as sheets;
import ballerinax/twilio.webhook;

configurable string twilio_callbackUrl = ?;
configurable string twilio_authToken = ?;

listener webhook:TwilioEventListener twilioListener = new (8080, twilio_authToken, twilio_callbackUrl);

configurable string sheets_refreshToken = ?;
configurable string sheets_clientId = ?;
configurable string sheets_clientSecret = ?;
configurable string sheets_spreadSheetID = ?;
configurable string sheets_workSheetName = ?;

sheets:SpreadsheetConfiguration spreadsheetConfig = {
    oauthClientConfig: {
        clientId: sheets_clientId,
        clientSecret: sheets_clientSecret,
        refreshUrl: sheets:REFRESH_URL,
        refreshToken: sheets_refreshToken
    }
};
sheets:Client spreadsheetClient = check new (spreadsheetConfig);

service / on twilioListener {
    resource function post subscriber(http:Caller caller, http:Request request) returns error? {

        var payload = check twilioListener.getEventType(caller, request);

        //Check for the event and get the status of the event.
        if (payload is webhook:SmsStatusChangeEvent) {
            if (payload.SmsStatus == webhook:RECEIVED) {
                string? messageBody = payload?.Body;
                if (messageBody is string) {

                    var decodedMessageBody = check encoding:decodeUriComponent(messageBody, "UTF-8");
                    string[] messageBodyParts = regex:split(decodedMessageBody, EMPTY_STRING);
                    string languageToVote = messageBodyParts[1];

                    // Get the values of the column A which contains the language list where the users vote.
                    var languageList = check spreadsheetClient->getColumn(sheets_spreadSheetID, sheets_workSheetName, 
                        COLUMN_NAME);

                    // Traverse through the language list and increment the vote count of the language sent by the user.
                    foreach var row in 1 ... languageList.length() {
                        var rowValue = languageList[row - 1];

                        if ((rowValue is string) && rowValue.equalsIgnoreCaseAscii(languageToVote)) {
                            var rowData = check spreadsheetClient->getRow(sheets_spreadSheetID, sheets_workSheetName, 
                                row);
                            int currentVoteCount = check ints:fromString(<string>rowData[1]);
                            string cellNumber = string `B${row}`;
                            (string|int)[] values = [languageToVote, currentVoteCount + 1];
                            var appendResult = check spreadsheetClient->setCell(sheets_spreadSheetID, 
                                sheets_workSheetName, cellNumber, <@untainted>currentVoteCount + 1);
                        } 
                    }
                }            
            } 
        } 
    }
}
