import sys

with open("earsonics/Views/AlbumDetailView.swift", "r") as f:
    text = f.read()

# We want to re-order the left panel `VStack(alignment: .leading, spacing: 16)` elements.
# The user wants "the action buttons go above it" (album art etc goes down).

import re

# We will match the entire VStack for the left panel.
# We know it starts at `// Left: Cover + info\n            VStack(alignment: .leading, spacing: 16) {`
# And ends before `// Right: Track list`

v_stack_regex = r"(// Left: Cover \+ info.*?VStack\([^)]*\) \{)(.*?)(// Actions\s+VStack\(spacing: 12\) \{.*?\n                \n                Spacer\(\)\n            \})\s*\.frame\(width: 360\)"
match = re.search(v_stack_regex, text, flags=re.DOTALL)

if match:
    vstack_start = match.group(1)
    metadata_body = match.group(2)
    actions_body = match.group(3)
    
    # We want to put actions_body BEFORE metadata_body
    new_text = f"{vstack_start}\n{actions_body}\n\n{metadata_body}            .frame(width: 360)"
    text = text[:match.start()] + new_text + text[match.end():]
    
    with open("earsonics/Views/AlbumDetailView.swift", "w") as f:
        f.write(text)
    print("Reordered successfully!")
else:
    print("Could not match regex")

