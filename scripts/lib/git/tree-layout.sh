#!/usr/bin/env bash
#
# Dev-Control Shared Library: Git Tree Fractal Layout (Pure Bash)
# Generates organic tree positions for git commits following actual git topology
#
# SPDX-Licence-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 xaoscience

# ============================================================================
# TREE LAYOUT CALCULATOR (PURE BASH + JQ)
# ============================================================================

# Calculate tree positions following real git topology
# Trunk grows upward, branches fork naturally, merge commits rejoin
calculate_tree_positions_bash() {
    local input_json="$1"
    local output_file="${2:-/tmp/git-tree-positions.json}"

    # Build a proper topological layout:
    # - x-axis: branch lanes (trunk at centre, branches fan out)
    # - y-axis: chronological order (newest at top, oldest at bottom)
    # Each branch gets its own lane; merges draw back to trunk
    jq '
        # Sort commits oldest-first (bottom of tree = oldest)
        .commits |= (sort_by(.timestamp) | reverse) |

        # Assign lane indices based on parent topology
        # Build parent->children map and detect branch points
        (.commits | length) as $total |
        600 as $centre_x |
        80 as $row_height |
        60 as $top_margin |
        120 as $lane_width |

        # Index commits by sha for fast lookup
        (.commits | map({(.sha): .}) | add // {}) as $by_sha |

        # Walk commits in topo order and assign lanes
        # First pass: detect which commits are branch tips vs trunk
        (.commits | map(.sha)) as $shas |
        (.commits | map(.parents // "" | split(" ") | map(select(. != "")))) as $parents_list |

        # Build children map: for each sha, which commits list it as parent
        (reduce range($total) as $i (
            {};
            ($parents_list[$i]) as $plist |
            reduce $plist[] as $p (.; .[$p] = ((.[$p] // []) + [$shas[$i]]))
        )) as $children_map |

        # Assign lanes: trunk = all commits reachable via first-parent chain from HEAD
        # Other commits get offset lanes
        (
            # Walk first-parent chain from newest commit
            [
                $shas[0] as $start |
                { current: $start, chain: [] } |
                until(
                    .current == null or (.current | length) == 0;
                    .chain += [.current] |
                    ($by_sha[.current] // null) as $c |
                    if $c == null then .current = null
                    else
                        ($c.parents // "" | split(" ") | map(select(. != ""))) as $pp |
                        if ($pp | length) > 0 then .current = $pp[0]
                        else .current = null
                        end
                    end
                ) |
                .chain
            ] | .[0]
        ) as $trunk_shas |

        # Map trunk shas for quick lookup
        ($trunk_shas | map({(.): true}) | add // {}) as $is_trunk |

        # Assign lane numbers: trunk=0, others get incrementing positive/negative lanes
        (
            reduce range($total) as $i (
                { lanes: {}, next_left: 1, next_right: 1 };
                $shas[$i] as $sha |
                if $is_trunk[$sha] then
                    .lanes[$sha] = 0
                else
                    # Alternate left and right
                    if (.next_left <= .next_right) then
                        .lanes[$sha] = .next_left |
                        .next_left += 1
                    else
                        .lanes[$sha] = (-.next_right) |
                        .next_right += 1
                    end
                end
            )
        ) as $lane_data |

        # Generate positions
        .commits |= [
            to_entries[] |
            .key as $idx |
            .value as $commit |
            ($lane_data.lanes[$commit.sha] // 0) as $lane |
            ($commit.parents // "" | split(" ") | map(select(. != "")) | length) as $parent_count |

            $commit + {
                position: {
                    x: ($centre_x + ($lane * $lane_width)),
                    y: ($top_margin + ($idx * $row_height)),
                    lane: $lane,
                    radius: (if $parent_count > 1 then 10 elif ($children_map[$commit.sha] // [] | length) > 1 then 9 else 6 end),
                    depth: $idx,
                    is_trunk: ($is_trunk[$commit.sha] // false),
                    is_merge: ($parent_count > 1),
                    is_fork: (($children_map[$commit.sha] // [] | length) > 1)
                }
            }
        ]
    ' "$input_json" > "$output_file" 2>/dev/null || {
        # Fallback if jq transform fails
        cp "$input_json" "$output_file"
    }

    echo "$output_file"
}

# Simpler linear tree layout (fallback if jq not available)
calculate_tree_positions_simple() {
    local input_json="$1"
    local output_file="${2:-/tmp/git-tree-positions.json}"

    jq '
        .commits |= (
            sort_by(.timestamp) | reverse |
            to_entries | map(
                .value + {
                    position: {
                        x: 600,
                        y: (80 + (.key * 80)),
                        lane: 0,
                        radius: 6,
                        depth: .key,
                        is_trunk: true,
                        is_merge: false,
                        is_fork: false
                    }
                }
            )
        )
    ' "$input_json" > "$output_file" 2>/dev/null || {
        cp "$input_json" "$output_file"
    }

    echo "$output_file"
}
