from pathlib import Path
text = Path('E:/dyna/scenes/world/world.tscn').read_text(encoding='utf-8')
print(text[:4000])
