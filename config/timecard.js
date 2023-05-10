function sync(doc, oldDoc, meta) {
    if (!doc.location_id) {
        console.log("Sync function: document does not have location_id key");
        return;
    }

    try {
        var locationId = doc.location_id;
        var username = "location_id@" + locationId;
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
