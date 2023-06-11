class DependencyManager
{
	string COLOR_RI = Icons::CheckCircle;
	string COLOR_OI = Icons::CheckCircleO;
	string COLOR_RN = Icons::Circle;
	string COLOR_ON = Icons::CircleO;

	uint DEPTH_LIMIT = 5;

	DepLeaf@[] seen; // used to prevent infinite loops
	DepLeaf@[] tree;
	string[] missing;

	bool showAllPlugins = false;
	bool m_visible = false;

	DependencyManager()
	{
		if (!Setting_ColorblindDependencies) {
			COLOR_RI = "\\$z" + COLOR_RI;
			COLOR_OI = "\\$666" + COLOR_OI;
			COLOR_RN = "\\$f00" + COLOR_RN;
			COLOR_ON = "\\$666" + COLOR_ON;
		}
	}

	void Render()
	{
		if (!m_visible) {
			return;
		}

		UI::SetNextWindowSize(800, 500);
		if (UI::Begin(Icons::CheckSquareO + " Dependency Auditor###PluginManagerDepAudit", m_visible)) {
			if (tree.Length == 0) {
				LoadDependencyTree();
			}

			if (UI::BeginTable("legend", 2, UI::TableFlags::SizingStretchSame)) {
				UI::TableNextRow();
				UI::TableNextColumn();
				UI::Text(COLOR_RI + "Required dependency");
				UI::TableNextColumn();
				UI::Text(COLOR_OI + "Optional dependency");
				UI::TableNextRow();
				UI::TableNextColumn();
			UI::Text(COLOR_RN + "Required dependency (not installed)");
				UI::TableNextColumn();
			UI::Text(COLOR_ON + "Optional dependency (not installed)");
				UI::EndTable();
				if (UI::Button("Rescan dependencies")) {
					LoadDependencyTree();
				}
				UI::SameLine();
				showAllPlugins = UI::Checkbox("List all plugins", showAllPlugins);
				if (UI::IsItemHovered()) {
					UI::BeginTooltip();
					UI::Text("If unchecked, only plugins with dependencies are listed");
					UI::EndTooltip();
				}
				UI::Separator();
			}

			for (uint i = 0; i < tree.Length; i++) {
				DrawPluginLeaf(tree[i], 0, true);
			}
		}
		UI::End();
	}

	void DrawPluginLeaf(DepLeaf@ plugin, uint depth, bool required)
	{
		string colorTag;

		if (plugin.m_plugin !is null) { // plugin is installed
			if (depth > 0) {
				colorTag = required ? COLOR_RI : COLOR_OI;
			}
			string pluginText;
			// check if it's an openplanet bundled plugin...
			if (plugin.m_plugin.Source == Meta::PluginSource::ApplicationFolder) {
				pluginText = "\\$f39" + Icons::Heartbeat + "\\$z" + plugin.m_name + " \\$666(built-in)";
			} else {
				pluginText = colorTag + InstalledPluginString(plugin);
			}
			// don't go too deep
			if (depth > DEPTH_LIMIT) {
				UI::TreeAdvanceToLabelPos();
				UI::Text(pluginText);
				return;
			} else {
				int numChilds = plugin.m_requiredChilds.Length + plugin.m_optionalChilds.Length;
				int flags = (numChilds == 0) ? UI::TreeNodeFlags::Leaf : UI::TreeNodeFlags::None;
				if (depth == 0) {
					flags |= UI::TreeNodeFlags::DefaultOpen;
					if (!showAllPlugins && numChilds == 0) {
						return;
					}
				}
				if (UI::TreeNode(pluginText+"###"+plugin.m_ident, flags)) {
					if (numChilds == 0 && depth == 0) {
						UI::TreeAdvanceToLabelPos();
						UI::Text("\\$666No dependencies");
					}
					for (uint i = 0; i < plugin.m_requiredChilds.Length; i++) {
						DrawPluginLeaf(plugin.m_requiredChilds[i], depth+1, true);
					}
					for (uint i = 0; i < plugin.m_optionalChilds.Length; i++) {
						DrawPluginLeaf(plugin.m_optionalChilds[i], depth+1, false);
					}
					UI::TreePop();
				}
			}

		} else if (plugin.m_apiObj !is null) { // we have openplanet.dev deets
			colorTag = required ? COLOR_RN : COLOR_ON;
			UI::TreeAdvanceToLabelPos();
			UI::Text(colorTag + NotInstalledPluginString(plugin) + "\\$z");
			UI::SameLine();
			if (UI::Button(Icons::InfoCircle + "###" + plugin.m_ident)) {
				g_window.m_visible = true;
				g_window.AddTab(PluginTab(plugin.m_siteID), true);
			}
		} else { // we got no fukken clue
			colorTag = required ? COLOR_RN : COLOR_ON;
			UI::TreeAdvanceToLabelPos();
			UI::Text(colorTag + MysteryPluginString(plugin) + "\\$z");
			UI::SameLine();
			if (UI::RedButton(Icons::ExclamationTriangle+ "###" + plugin.m_ident)) {
				OpenBrowserURL("https://openplanet.dev/plugin/"+plugin.m_ident);
			}
			if (UI::IsItemHovered()) {
				UI::BeginTooltip();
				UI::Text("Plugin identifier not found. Click to search on Openplanet.dev.");
				UI::EndTooltip();
			}
		}
	}

	string InstalledPluginString(DepLeaf@ plugin)
	{
		return plugin.m_name +
			" \\$999by " + plugin.m_author +
			" \\$666(" + plugin.m_plugin.Version + " installed)";
	}

	string NotInstalledPluginString(DepLeaf@ plugin)
	{
		return plugin.m_name +
			" \\$999by " + plugin.m_author;
	}

	string MysteryPluginString(DepLeaf@ plugin)
	{
		return plugin.m_ident;
	}

	void LoadDependencyTree(bool retryMissing = true)
	{
		trace("Reloading dependency tree...");
		seen.Resize(0);
		tree.Resize(0);
		missing.Resize(0);

		// first let's populate our top-levels
		Meta::Plugin@[] loaded = Meta::AllPlugins();
		for (uint i = 0; i < loaded.Length; i++) {
			Meta::Plugin@ v = loaded[i];
			DepLeaf x = DepLeaf(loaded[i]);
			tree.InsertLast(x);
			seen.InsertLast(x);
		}

		// now iterate through and add dependencies
		for (uint i = 0; i < tree.Length; i++) {
			tree[i].PopulateChilds(seen);
		}
		trace("Scanned " + seen.Length + " plugins.");

		if (retryMissing) { // avoid infinite loop
			API::GetPluginListAsync(missing);
			LoadDependencyTree(false);
		}
	}

	bool isMissingRequirements()
	{
		for (uint i = 0; i < tree.Length; i++) {
			if (tree[i].isMissingRequirements()) {
				return true;
			}
		}
		return false;
	}

	bool isMissingOptionals()
	{
		for (uint i = 0; i < tree.Length; i++) {
			if (tree[i].isMissingOptionals()) {
				return true;
			}
		}
		return false;
	}
}

DependencyManager g_dependencyManager;