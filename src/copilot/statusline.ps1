$ErrorActionPreference = 'Continue'

try {
    $payload = [Console]::In.ReadToEnd()

    if ([string]::IsNullOrWhiteSpace($payload)) {
        [Console]::Out.Write('Copilot status unavailable')
        return
    }

    try {
        $json = $payload | ConvertFrom-Json -ErrorAction Stop
    } catch {
        [Console]::Out.Write('Copilot status unavailable')
        return
    }

    $cwd = $json.cwd
    if (-not $cwd -and $json.workspace) { $cwd = $json.workspace.current_dir }
    if (-not $cwd) { $cwd = [System.IO.Directory]::GetCurrentDirectory() }
    $cwdLeaf = [System.IO.Path]::GetFileName($cwd)
    if ([string]::IsNullOrEmpty($cwdLeaf)) { $cwdLeaf = $cwd }

    $branch = $null
    $cur = $cwd
    while (-not [string]::IsNullOrEmpty($cur)) {
        $candidate = [System.IO.Path]::Combine($cur, '.git')
        if ([System.IO.Directory]::Exists($candidate)) {
            $head = [System.IO.Path]::Combine($candidate, 'HEAD')
            if ([System.IO.File]::Exists($head)) {
                $line = [System.IO.File]::ReadAllText($head).Trim()
                if ($line.StartsWith('ref: refs/heads/')) {
                    $branch = $line.Substring(16)
                } elseif ($line.Length -ge 7) {
                    $branch = '@' + $line.Substring(0, 7)
                }
            }
            break
        }
        if ([System.IO.File]::Exists($candidate)) {
            $line = [System.IO.File]::ReadAllText($candidate).Trim()
            if ($line.StartsWith('gitdir:')) {
                $resolved = $line.Substring(7).Trim()
                if (-not [System.IO.Path]::IsPathRooted($resolved)) {
                    $resolved = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($cur, $resolved))
                }
                $head = [System.IO.Path]::Combine($resolved, 'HEAD')
                if ([System.IO.File]::Exists($head)) {
                    $hline = [System.IO.File]::ReadAllText($head).Trim()
                    if ($hline.StartsWith('ref: refs/heads/')) {
                        $branch = $hline.Substring(16)
                    } elseif ($hline.Length -ge 7) {
                        $branch = '@' + $hline.Substring(0, 7)
                    }
                }
            }
            break
        }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if ($parent -eq $cur -or [string]::IsNullOrEmpty($parent)) { break }
        $cur = $parent
    }

    $ctx  = $json.context_window
    $cost = $json.cost

    $currentTokens  = if ($ctx) { $ctx.current_context_tokens } else { $null }
    $contextLimit   = if ($ctx) { if ($null -ne $ctx.displayed_context_limit) { $ctx.displayed_context_limit } else { $ctx.context_window_size } } else { $null }
    $contextPercent = if ($ctx) { if ($null -ne $ctx.current_context_used_percentage) { $ctx.current_context_used_percentage } else { $ctx.used_percentage } } else { $null }

    $durationMs   = if ($cost) { $cost.total_duration_ms } else { $null }
    $linesAdded   = if ($cost -and $null -ne $cost.total_lines_added)   { [int]$cost.total_lines_added }   else { 0 }
    $linesRemoved = if ($cost -and $null -ne $cost.total_lines_removed) { [int]$cost.total_lines_removed } else { 0 }

    function fmt($v) {
        if ($null -eq $v) { return '?' }
        $d = [double]$v
        if ($d -ge 1000000) { return ('{0:0.0}m' -f ($d / 1000000)) }
        if ($d -ge 1000)    { return ('{0:0.0}k' -f ($d / 1000)) }
        return ([int]$d).ToString()
    }
    $ctxStr = (fmt $currentTokens) + '/' + (fmt $contextLimit)

    $w = 20
    if ($null -eq $contextPercent) {
        $bar = [string]::new([char]'.', $w); $barColor = "`e[2m"
    } else {
        $b = [Math]::Max(0.0, [Math]::Min(100.0, [double]$contextPercent))
        $f = [int]($b * $w / 100.0)
        $bar = [string]::new([char]'#', $f) + [string]::new([char]'.', $w - $f)
        $barColor = if ($b -ge 90) { "`e[31m" } elseif ($b -ge 70) { "`e[33m" } else { "`e[32m" }
    }

    if ($null -eq $durationMs -or [double]$durationMs -le 0) {
        $duration = '00:00:00'
    } else {
        $d = [TimeSpan]::FromMilliseconds([double]$durationMs)
        $duration = '{0:00}:{1:00}:{2:00}' -f [int]$d.TotalHours, $d.Minutes, $d.Seconds
    }

    $sb = [System.Text.StringBuilder]::new(160)
    [void]$sb.Append("`e[33m[").Append($cwdLeaf).Append("]`e[0m")
    if ($branch) { [void]$sb.Append(" `e[34m[git: ").Append($branch).Append("]`e[0m") }
    [void]$sb.Append(" `e[36m[ctx ").Append($ctxStr).Append("]`e[0m")
    [void]$sb.Append(' ').Append($barColor).Append('[').Append($bar).Append("]`e[0m")
    [void]$sb.Append(" `e[35m[").Append($duration).Append("]`e[0m")
    if ($linesAdded -ne 0 -or $linesRemoved -ne 0) {
        [void]$sb.Append(" `e[32m[+").Append($linesAdded).Append("`e[2m/`e[0m`e[31m-").Append($linesRemoved).Append("]`e[0m")
    }

    [Console]::Out.Write($sb.ToString())
} catch {
    [Console]::Out.Write('Copilot status unavailable')
}
