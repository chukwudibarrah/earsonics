with open("earsonics/Views/AlbumDetailView.swift", "r") as f:
    text = f.read()

start_idx = text.find("// Left: Cover + info\n            VStack(alignment: .leading, spacing: 16) {")
actions_idx = text.find("                // Actions\n                VStack(spacing: 12) {")
end_idx = text.find("                Spacer()\n            }\n            .frame(width: 360)")

if start_idx != -1 and actions_idx != -1 and end_idx != -1:
    metadata_part = text[start_idx + len("// Left: Cover + info\n            VStack(alignment: .leading, spacing: 16) {\n"):actions_idx]
    actions_part = text[actions_idx:end_idx]
    
    # Let's put actions at the top of the VStack
    new_left = f"""// Left: Cover + info
            VStack(alignment: .leading, spacing: 16) {{
{actions_part}
{metadata_part}"""
    
    text = text[:start_idx] + new_left + text[end_idx:]
    with open("earsonics/Views/AlbumDetailView.swift", "w") as f:
        f.write(text)
    print("Reordered")
else:
    print("Could not find sections:", start_idx, actions_idx, end_idx)

