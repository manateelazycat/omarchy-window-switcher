function syncWorkspaceModel(model, ids) {
    const wanted = ({});
    for (const id of ids)
        wanted[id] = true;
    for (let i = model.count - 1; i >= 0; --i) {
        if (!wanted[model.get(i).workspaceId])
            model.remove(i);
    }

    for (let i = 0; i < ids.length; ++i) {
        if (i < model.count && model.get(i).workspaceId === ids[i])
            continue;
        let oldIndex = -1;
        for (let j = i + 1; j < model.count; ++j) {
            if (model.get(j).workspaceId === ids[i]) {
                oldIndex = j;
                break;
            }
        }
        if (oldIndex >= 0)
            model.move(oldIndex, i, 1);
        else
            model.insert(i, { workspaceId: ids[i] });
    }
}

if (typeof module !== "undefined")
    module.exports = { syncWorkspaceModel };
