function sync(doc, oldDoc, meta) {
    if (doc._deleted) {
        return;
    }

    if (!doc.store_id) {
        console.log("Sync function: document does not have store_id key");
        return;
    }

    try {
        var storeId = doc.store_id;
        var username = "store_id@" + storeId;
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
