<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('br_states')) {
            Schema::create('br_states', function (Blueprint $table) {
                $table->id();
                $table->unsignedInteger('ibge_code')->unique();
                $table->string('name', 120);
                $table->string('uf_code', 2)->unique();
                $table->string('region_name', 80)->nullable();
                $table->unsignedInteger('region_ibge_code')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('br_cities')) {
            Schema::create('br_cities', function (Blueprint $table) {
                $table->id();
                $table->foreignId('state_id')->nullable()->index();
                $table->unsignedBigInteger('ibge_code')->unique();
                $table->string('name', 160);
                $table->string('slug', 191)->nullable()->index();
                $table->timestamps();

                $table->unique(['state_id', 'name']);
            });
        }

        if (!Schema::hasTable('br_neighborhoods')) {
            Schema::create('br_neighborhoods', function (Blueprint $table) {
                $table->id();
                $table->foreignId('city_id')->nullable()->index();
                $table->string('name', 180);
                $table->string('name_normalized', 191)->index();
                $table->string('external_code', 64)->nullable()->index();
                $table->timestamps();

                $table->unique(['city_id', 'name_normalized'], 'uq_neighborhood_city_name_norm');
            });
        }

        if (!Schema::hasTable('postal_code_ranges')) {
            Schema::create('postal_code_ranges', function (Blueprint $table) {
                $table->id();
                $table->foreignId('state_id')->nullable()->index();
                $table->foreignId('city_id')->nullable()->index();
                $table->foreignId('neighborhood_id')->nullable()->index();
                $table->string('cep_start', 8);
                $table->string('cep_end', 8);
                $table->string('range_key', 64)->unique();
                $table->timestamps();

                $table->index(['city_id', 'cep_start', 'cep_end']);
            });
        }

        if (Schema::hasTable('br_states') && Schema::hasTable('br_cities')) {
            Schema::table('br_cities', function (Blueprint $table) {
                $table->foreign('state_id')->references('id')->on('br_states')->nullOnDelete();
            });
        }

        if (Schema::hasTable('br_cities') && Schema::hasTable('br_neighborhoods')) {
            Schema::table('br_neighborhoods', function (Blueprint $table) {
                $table->foreign('city_id')->references('id')->on('br_cities')->nullOnDelete();
            });
        }

        if (Schema::hasTable('postal_code_ranges')) {
            Schema::table('postal_code_ranges', function (Blueprint $table) {
                if (Schema::hasTable('br_states')) {
                    $table->foreign('state_id')->references('id')->on('br_states')->nullOnDelete();
                }
                if (Schema::hasTable('br_cities')) {
                    $table->foreign('city_id')->references('id')->on('br_cities')->nullOnDelete();
                }
                if (Schema::hasTable('br_neighborhoods')) {
                    $table->foreign('neighborhood_id')->references('id')->on('br_neighborhoods')->nullOnDelete();
                }
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('postal_code_ranges');
        Schema::dropIfExists('br_neighborhoods');
        Schema::dropIfExists('br_cities');
        Schema::dropIfExists('br_states');
    }
};
