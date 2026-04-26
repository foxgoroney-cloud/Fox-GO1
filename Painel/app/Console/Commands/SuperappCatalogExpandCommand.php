<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\SuperappTracksJobs;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class SuperappCatalogExpandCommand extends Command
{
    use SuperappTracksJobs;

    protected $signature = 'superapp:catalog-expand {--module-types=food,grocery,pharmacy,ecommerce,parcel} {--dry-run}';
    protected $description = 'Expande estrutura de catálogo nacional (infra idempotente)';

    public function handle(): int
    {
        $dryRun = (bool)$this->option('dry-run');
        $types = array_filter(array_map('trim', explode(',', (string)$this->option('module-types'))));
        $this->startSuperappJob($this->getName(), 'generated', $this->options(), $dryRun);

        foreach ($types as $type) {
            $module = DB::table('modules')->where('module_type', $type)->orderBy('id')->first();
            if (!$module) {
                $this->logImportError(0, $type, 'Module type not found');
                continue;
            }

            for ($i = 1; $i <= 25; $i++) {
                $rootName = strtoupper($type) . " ROOT {$i}";
                $root = DB::table('categories')->where('module_id', $module->id)->where('parent_id', 0)->where('name', $rootName)->first();
                $this->jobStats['processed_rows']++;

                if (!$dryRun && !$root) {
                    $rootId = DB::table('categories')->insertGetId([
                        'name' => $rootName,
                        'image' => 'def.png',
                        'parent_id' => 0,
                        'position' => 0,
                        'priority' => 0,
                        'module_id' => $module->id,
                        'status' => 1,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                    $this->jobStats['inserted_rows']++;
                } else {
                    $rootId = $root->id ?? 0;
                    $this->jobStats[$root ? 'updated_rows' : 'inserted_rows']++;
                }

                if ($rootId && !$dryRun) {
                    for ($s = 1; $s <= 5; $s++) {
                        DB::table('categories')->updateOrInsert(
                            ['module_id' => $module->id, 'parent_id' => $rootId, 'position' => 1, 'name' => "{$rootName} SUB {$s}"],
                            ['image' => 'def.png', 'priority' => 0, 'status' => 1, 'updated_at' => now(), 'created_at' => now()]
                        );
                    }
                }
            }
        }

        $manifest = $this->createManifest($this->getName(), ['stats' => $this->jobStats, 'dry_run' => $dryRun]);
        $this->finishSuperappJob($this->jobStats['error_rows'] ? 'completed_with_errors' : 'completed', $manifest, 'Catalog expansion infra done');

        return self::SUCCESS;
    }
}
