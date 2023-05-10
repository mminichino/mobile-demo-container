function sync(doc, oldDoc, meta) {
    if (!doc.region) {
        console.log("Sync function: document does not have division key");
        return;
    }

    try {
        var region = doc.region;
        var username = "region@" + region;
        var channelId = "channel." + username;

        console.log("Processing doc for channel " + channelId);
        requireUser(username);
        channel(channelId);
        access(username,channelId);
    } catch (error) {
        console.log("Sync function error: " + error.message);
        throw({forbidden: error.message});
    }
}
