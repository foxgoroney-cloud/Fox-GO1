<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('zone_regions')) {
            Schema::create('zone_regions', function (Blueprint $table) {
                $table->id();
                $table->string('code', 64)->unique();
                $table->string('name', 191);
                $table->foreignId('state_id')->nullable()->index();
                $table->foreignId('city_id')->nullable()->index();
                $table->enum('zone_type', ['active', 'surge'])->default('active')->index();
                $table->string('strategy', 64)->default('city_cluster')->index();
                $table->boolean('is_enabled')->default(true);
                $table->json('meta')->nullable();
                $table->timestamps();

                $table->unique(['city_id', 'zone_type', 'name'], 'uq_zone_regions_city_type_name');
            });
        }

        if (!Schema::hasTable('zone_region_polygons')) {
            Schema::create('zone_region_polygons', function (Blueprint $table) {
                $table->id();
                $table->foreignId('zone_region_id')->index();
                $table->unsignedInteger('version')->default(1);
                $table->json('coordinates');
                $table->boolean('is_closed')->default(false)->index();
                $table->timestamps();

                $table->unique(['zone_region_id', 'version']);
            });
        }

        if (!Schema::hasTable('zone_region_neighborhoods')) {
            Schema::create('zone_region_neighborhoods', function (Blueprint $table) {
                $table->id();
                $table->foreignId('zone_region_id')->index();
                $table->foreignId('neighborhood_id')->index();
                $table->timestamps();

                $table->unique(['zone_region_id', 'neighborhood_id'], 'uq_zone_region_neighborhood');
            });
        }

        if (!Schema::hasTable('zone_region_modules')) {
            Schema::create('zone_region_modules', function (Blueprint $table) {
                $table->id();
                $table->foreignId('zone_region_id')->index();
                $table->unsignedBigInteger('module_id')->index();
                $table->boolean('is_enabled')->default(true);
                $table->timestamps();

                $table->unique(['zone_region_id', 'module_id'], 'uq_zone_region_module');
            });
        }

        if (Schema::hasTable('zone_regions')) {
            Schema::table('zone_regions', function (Blueprint $table) {
                if (Schema::hasTable('br_states')) {
                    $table->foreign('state_id')->references('id')->on('br_states')->nullOnDelete();
                }
                if (Schema::hasTable('br_cities')) {
                    $table->foreign('city_id')->references('id')->on('br_cities')->nullOnDelete();
                }
            });
        }

        if (Schema::hasTable('zone_region_polygons')) {
            Schema::table('zone_region_polygons', function (Blueprint $table) {
                if (Schema::hasTable('zone_regions')) {
                    $table->foreign('zone_region_id')->references('id')->on('zone_regions')->cascadeOnDelete();
                }
            });
        }

        if (Schema::hasTable('zone_region_neighborhoods')) {
            Schema::table('zone_region_neighborhoods', function (Blueprint $table) {
                if (Schema::hasTable('zone_regions')) {
                    $table->foreign('zone_region_id')->references('id')->on('zone_regions')->cascadeOnDelete();
                }
                if (Schema::hasTable('br_neighborhoods')) {
                    $table->foreign('neighborhood_id')->references('id')->on('br_neighborhoods')->cascadeOnDelete();
                }
            });
        }

        if (Schema::hasTable('zone_region_modules')) {
            Schema::table('zone_region_modules', function (Blueprint $table) {
                if (Schema::hasTable('zone_regions')) {
                    $table->foreign('zone_region_id')->references('id')->on('zone_regions')->cascadeOnDelete();
                }
                if (Schema::hasTable('modules')) {
                    $table->foreign('module_id')->references('id')->on('modules')->cascadeOnDelete();
                }
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('zone_region_modules');
        Schema::dropIfExists('zone_region_neighborhoods');
        Schema::dropIfExists('zone_region_polygons');
        Schema::dropIfExists('zone_regions');
    }
};
