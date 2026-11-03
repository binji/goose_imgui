# Benchmark results

`bench/bench.goose`: a scroll pane of rows (a label, a button, a checkbox,
a slider and a progress bar; 15 nodes a row), recorded, laid out and drawn
headless into a 1280×720 target, averaged over 60 frames after 10. "Draw"
is imgui's walk recording into gfx2d plus gfx2d's own `end()`, its GPU
submission included. Rows scrolled out of the pane are culled, so drawing
costs what is on the screen, not what is in the tree.

Arch Linux in WSL2 on an i9-13900KF, an RTX 3070 Ti through Mesa's dzn
(Vulkan over D3D12); Goose 2ed1a63d.

| | nodes | record | layout | draw |
|---|---:|---:|---:|---:|
| JIT (TinyCC), 250 rows | 3,754 | 6.03 ms | 1.44 ms | 2.65 ms |
| AOT, 250 rows | 3,754 | 0.60 ms | 0.26 ms | 2.25 ms |
| AOT, 1,000 rows | 15,004 | 2.47 ms | 1.72 ms | 2.54 ms |

Before culling, drawing 250 rows took 9.75 ms (AOT), and 1,000 rows 29.1 ms.

    goose bench/bench.goose -- 250                       # JIT
    goose build bench/bench.goose -o bench && ./bench 250  # AOT
