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
        # Topological sort: respect parent→child ordering as primary key,
        # timestamp as secondary. This ensures merges never appear before
        # their parent commits even when timestamps are identical.
        (
            # Build parent→children and child→parent maps
            (.commits | map({(.sha): .}) | add // {}) as $by_sha |
            (.commits | map(.sha)) as $all_shas |
            (reduce .commits[] as $c (
                {};
                ($c.parents // "" | split(" ") | map(select(. != ""))) as $pp |
                reduce $pp[] as $p (.; .[$p] = ((.[$p] // []) + [$c.sha]))
            )) as $children_map |

            # Kahn topological sort (oldest-first): start from root commits
            # (commits with no parents or no known parents in our set)
            (reduce .commits[] as $c (
                {};
                ($c.parents // "" | split(" ") | map(select(. != "" and $by_sha[.] != null))) as $known |
                .[$c.sha] = ($known | length)
            )) as $in_degree |

            {
                queue: [$all_shas[] | select($in_degree[.] == 0)] |
                    sort_by($by_sha[.].timestamp),
                result: [],
                visited: {},
                in_deg: $in_degree
            } |
            until(
                (.queue | length) == 0;
                # Sort queue by timestamp so same-depth commits appear in time order
                .queue |= sort_by($by_sha[.].timestamp) |
                .queue[0] as $sha |
                .queue = .queue[1:] |
                if .visited[$sha] then .
                else
                    .visited[$sha] = true |
                    .result += [$by_sha[$sha]] |
                    # Add children whose in-degree reaches 0
                    reduce ($children_map[$sha] // [])[] as $child (
                        .;
                        .in_deg[$child] = ((.in_deg[$child] // 1) - 1) |
                        if .in_deg[$child] <= 0 and (.visited[$child] // false | not) then
                            .queue += [$child]
                        else . end
                    )
                end
            ) |
            .result | reverse
        ) as $sorted |

        .commits = $sorted |

        # Assign lane indices based on parent topology
        (.commits | length) as $total |
        600 as $centre_x |
        40 as $trunk_row_height |
        80 as $branch_row_height |
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

        # Generate positions with variable row heights
        # Trunk commits use smaller spacing, branch commits use larger
        .commits |= (
            reduce to_entries[] as $entry (
                { result: [], y: $top_margin };
                $entry.key as $idx |
                $entry.value as $commit |
                ($lane_data.lanes[$commit.sha] // 0) as $lane |
                ($commit.parents // "" | split(" ") | map(select(. != "")) | length) as $parent_count |
                (if $is_trunk[$commit.sha] then $trunk_row_height else $branch_row_height end) as $step |
                .y as $cur_y |
                .result += [
                    $commit + {
                        position: {
                            x: ($centre_x + ($lane * $lane_width)),
                            y: $cur_y,
                            lane: $lane,
                            radius: (if $parent_count > 1 then 10 elif ($children_map[$commit.sha] // [] | length) > 1 then 9 else 6 end),
                            depth: $idx,
                            is_trunk: ($is_trunk[$commit.sha] // false),
                            is_merge: ($parent_count > 1),
                            is_fork: (($children_map[$commit.sha] // [] | length) > 1)
                        }
                    }
                ] |
                .y += $step
            ) |
            .result
        )
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
