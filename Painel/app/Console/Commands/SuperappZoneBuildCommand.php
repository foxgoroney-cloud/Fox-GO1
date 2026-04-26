<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SuperappZoneBuildCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:zone-build {--strategy=city_cluster} {--target-active=25000} {--target-surge=10000} {--dry-run}';
    protected $description = 'Gera zone_regions e polígonos com estratégia escalável/idempotente';

    public function handle(): int
    {
        $dryRun = (bool)$this->option('dry-run');
        $strategy = (string)$this->option('strategy');
        $targetActive = max(0, (int)$this->option('target-active'));
        $targetSurge = max(0, (int)$this->option('target-surge'));

        $this->startSuperappJob($this->getName(), 'generated', $this->options(), $dryRun);

        $cities = DB::table('br_cities')->orderBy('id')->get(['id', 'state_id', 'name']);
        $activeCount = 0;
        $surgeCount = 0;

        foreach ($cities as $city) {
            foreach (['active', 'surge'] as $type) {
                if ($type === 'active' && $activeCount >= $targetActive) {
                    continue;
                }
                if ($type === 'surge' && $surgeCount >= $targetSurge) {
                    continue;
                }

                $this->jobStats['processed_rows']++;
                $code = sprintf('BR-%d-%s-01', $city->id, strtoupper($type));
                $name = $city->name . ' ' . strtoupper($type);
                $exists = DB::table('zone_regions')->where('code', $code)->first();

                if (!$dryRun) {
                    DB::table('zone_regions')->updateOrInsert(
                        ['code' => $code],
                        [
                            'name' => $name,
                            'state_id' => $city->state_id,
                            'city_id' => $city->id,
                            'zone_type' => $type,
                            'strategy' => $strategy,
                            'meta' => json_encode(['generated' => true]),
                            'is_enabled' => 1,
                            'updated_at' => now(),
                            'created_at' => now(),
                        ]
                    );

                    $zoneRegionId = DB::table('zone_regions')->where('code', $code)->value('id');
                    $polygon = [[[-15.0, -47.0], [-15.0, -46.9], [-15.1, -46.9], [-15.1, -47.0], [-15.0, -47.0]]];
                    $closed = $this->isPolygonClosed($polygon);
                    if (!$closed) {
                        $this->logImportError((int)$this->jobStats['processed_rows'], $code, 'Polygon is not closed', ['coordinates' => $polygon]);
                    } else {
                        DB::table('zone_region_polygons')->updateOrInsert(
                            ['zone_region_id' => $zoneRegionId, 'version' => 1],
                            [
                                'coordinates' => json_encode($polygon, JSON_UNESCAPED_UNICODE),
                                'is_closed' => 1,
                                'updated_at' => now(),
                                'created_at' => now(),
                            ]
                        );
                    }
                }

                $this->jobStats[$exists ? 'updated_rows' : 'inserted_rows']++;
                $type === 'active' ? $activeCount++ : $surgeCount++;
            }

            if ($activeCount >= $targetActive && $surgeCount >= $targetSurge) {
                break;
            }
        }

        $manifest = $this->createManifest($this->getName(), ['stats' => $this->jobStats, 'active' => $activeCount, 'surge' => $surgeCount, 'dry_run' => $dryRun]);
        $this->finishSuperappJob($this->jobStats['error_rows'] ? 'completed_with_errors' : 'completed', $manifest, 'Zone build done');

        return self::SUCCESS;
    }

    private function isPolygonClosed(array $polygon): bool
    {
        $ring = $polygon[0] ?? [];
        if (count($ring) < 4) {
            return false;
        }

        $first = $ring[0];
        $last = $ring[count($ring) - 1];

        return isset($first[0], $first[1], $last[0], $last[1])
            && (float)$first[0] === (float)$last[0]
            && (float)$first[1] === (float)$last[1];
    }
}
