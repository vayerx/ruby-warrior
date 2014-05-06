class Player
  ALL_DIRS = [:left, :forward, :right, :backward]
  MAX_HEALTH = 20
  BOMB_NEAR_DMG = 8
  BOMB_SELF_DMG = 4
  ATTACK_POWER = 5

  def initialize
    @captives = nil
    @captives_amount = nil
    @bound_amount = 0
    @bound_dirs = []
    @bound_damage = 0
    @evacuation_dir = nil
    @kill_with_power = nil  # remote bombing mode
    @escaping_enemies = 0   # amount of enemies that will survive bombing
  end

  def play_turn(warrior)
    units = detect_units(warrior)
    @captives = units.select{ |space| space.respond_to?(:captive?) && space.captive? } if @captives.nil?
    @captives_amount = @captives.size if @captives_amount.nil?

    if @captive_dir
      @captives_amount -= 1 if warrior.feel(@captive_dir).empty?
      @bound_amount -= 1 if warrior.feel(@captive_dir).enemy?
      @bound_damage = 0 unless @bound_amount
      @captive_dir = nil
    end

    if units.empty? && !@evacuation_dir
        get_me_out_of_here(warrior)   # no one left
    else
      enemy_dirs = get_nearby_units_dirs(warrior, :enemy?)
      ticking = units.select{ |space| space.respond_to?(:ticking?) && space.ticking? }  # lets check if enemy can tick ;)
      if ticking.empty?
        clean_em_up(warrior, units, enemy_dirs, units)
      else  # bomb!!!11
        clean_em_up(warrior, ticking, enemy_dirs, units, :hurry)
      end
    end
  end

  def clean_em_up(warrior, target_units, enemy_dirs, all_units, hurry = false)
    min_health = [hurry ? MAX_HEALTH/2 : MAX_HEALTH, 1 + damage_estimate(all_units) + @bound_damage].min

    if @kill_with_power
      if all_units.count{ |space| space.enemy? } == @escaping_enemies
        # condemned enemies are dead
        @kill_with_power = nil
      else
        return warrior.health <= BOMB_SELF_DMG ? warrior.rest! : warrior.detonate!(@kill_with_power)
      end
    end

    # handle surrunding
    if enemy_dirs.size > 1
      stepback = ALL_DIRS.find{ |dir| warrior.feel(dir).empty? }
      if warrior.respond_to?(:detonate!) && stepback && get_captive_distance(warrior) > 1
        # bomb 'em!!!1
        @kill_with_power = opposite_direction(stepback)
        @escaping_enemies = all_units.count{ |space| space.enemy? } - enemy_dirs.size
        return move(warrior, stepback)
      else
        # just bind some
        target_dir = warrior.respond_to?(:direction_of) ? warrior.direction_of(target_units[0]) : :none
        enemy_dir = enemy_dirs.find { |dir| dir != target_dir }  # out-of-way enemy
        return bind_enemy(warrior, enemy_dir) if enemy_dir
      end
    end

    # am I dying?
    return evacuate(warrior, enemy_dirs) if !hurry && need_evacuation?(warrior, enemy_dirs)

    # am I bleeding in a safe place?
    return warrior.rest! if need_a_rest(warrior, min_health, enemy_dirs, all_units, hurry)

    # look around for enemies
    local_damage_estimate = damage_estimate(enemy_dirs.map{ |d| warrior.feel(d) })
    return self if handle_units(warrior, target_units, :enemy?) do |space, dir|
      # TODO find direction with the most amount of enemies
      attack(warrior, dir, local_damage_estimate)
    end
    return attack(warrior, @bound_dirs.shift, local_damage_estimate) unless @bound_dirs.empty? || hurry

    # look around for victims
    return self if handle_units(warrior, target_units, :captive?) do |space, dir|
      warrior.rescue!(dir)
      @captives.delete(space) # doesn't work ;(
      @captive_dir = dir
    end

    # go further
    select_walking_direction(warrior, target_units) do |dir|
      if (!warrior.feel(dir).empty? || warrior.feel(dir).stairs?) && !warrior.feel(dir).enemy?
        dir = detour_heuristics(warrior, dir)
      end
      if warrior.feel(dir).empty?
        move(warrior, dir)
        break :done
      end
    end
  end

  def get_captive_distance(warrior)
    @captives.map{ |space| warrior.distance_of(space) }.min || raise rescue 10
  end

  def can_detonate?(warrior, damage_estimate)
    captive_distance = get_captive_distance(warrior)
    warrior.respond_to?(:detonate!) && captive_distance > 2 && warrior.health > BOMB_SELF_DMG + damage_estimate
  end

  def attack(warrior, dir, damage_estimate)
    if can_detonate?(warrior, damage_estimate)
      warrior.detonate!(dir)
    else
      warrior.attack!(dir)
    end
  end

  def need_a_rest(warrior, min_health, enemy_dirs, all_units, hurry)
    return false if warrior.health >= min_health || !enemy_dirs.empty?
    return true if @evacuation_dir
    return false if all_units.size == @captives_amount && warrior.respond_to?(:listen)
    return false if (hurry || @bound_amount == 0) && (@bound_amount + @captives_amount == all_units.size)
    return true
  end

  def unit_damage(unit, mode=:sword)
    first_strike_bonus = 1    # always first strike
    power = (mode == :bomb) ? BOMB_NEAR_DMG : ATTACK_POWER
    bomb_penalty = (mode == :bomb) ? BOMB_SELF_DMG : 0
    (unit.health.fdiv(power).ceil - first_strike_bonus) * (unit.attack_power + bomb_penalty)
  end

  def _damage_estimate(units, mode)
    units.select{ |space| space.enemy? }.map{ |enemy| unit_damage(enemy.unit, mode) }.reduce(:+) || 0
  end

  def damage_estimate(units)
    # TODO fix for multiple units
    sword_estimate = _damage_estimate(units, :sword)
    bomb_estimate = _damage_estimate(units, :bomb)
    [sword_estimate, bomb_estimate].min
  end

  def select_walking_direction(warrior, units)
    if @evacuation_dir
      yield opposite_direction(@evacuation_dir)
      @evacuation_dir = nil
    elsif warrior.respond_to?(:direction_of)
      units.each do |space|
        return self if yield(warrior.direction_of(space)) == :done
      end
    else
      yield warrior.direction_of_stairs
    end
  end

  def handle_units(warrior, units, check)
    if warrior.respond_to?(:direction_of)
      units.each do |space|
        dir = warrior.direction_of(space)
        if warrior.feel(dir).send(check)
          yield space, dir
          return true
        end
      end
    else
      ALL_DIRS.each do |dir|
        if warrior.feel(dir).send(check)
          yield nil, dir
          return true
        end
      end
    end
    return false
  end

  def get_me_out_of_here(warrior)
    dir = warrior.direction_of_stairs
    move(warrior, if warrior.feel(dir).empty? then dir else detour_heuristics(warrior, dir) end)
  end

  def detect_units(warrior)
    if warrior.respond_to?(:listen)
      warrior.listen
    else
      (get_nearby_units_dirs(warrior, :enemy?) + get_nearby_units_dirs(warrior, :captive?)).map{ |d| warrior.feel(d) }
    end
  end

  def get_nearby_units_dirs(warrior, type_check)
    ALL_DIRS.select { |dir| warrior.feel(dir).send(type_check) }
  end

  def detour_heuristics(warrior, dir)
    detour = {
      :left     => :forward,
      :forward  => :right,
      :right    => :backward,
      :backward => :left
    }[dir]
    # ... or try opposite route...
    if !warrior.feel(detour).empty? || !warrior.feel(detour).stairs? || !warrior.feel(detour).wall?
      detour = opposite_direction(detour)
    end
    return detour
  end

  def opposite_direction(dir)
    { :left     => :right,
      :forward  => :backward,
      :right    => :left,
      :backward => :forward
    }[dir]
  end

  def bind_enemy(warrior, dir)
    @bound_amount += 1
    @bound_dirs << dir
    @bound_damage = unit_damage(warrior.feel(dir).unit)
    warrior.bind!(dir)
  end

  def need_evacuation?(warrior, enemy_dirs)
    required_health = 1 + (enemy_dirs.map{ |dir| warrior.feel(dir).unit.attack_power }.reduce(:+) || 0)

    # check if warrior any enemy will die this turn
    dying_enemy_dir = enemy_dirs.find{ |dir| warrior.feel(dir).enemy? && warrior.feel(dir).unit.health <= ATTACK_POWER }
    required_health -= warrior.feel(dying_enemy_dir).unit.attack_power if dying_enemy_dir

    return warrior.health < required_health && ALL_DIRS.any? { |d| warrior.feel(d).empty? }
  end

  def evacuate(warrior, enemy_dirs)
    if warrior.respond_to?(:bind!) && enemy_dirs.size == 1
      bind_enemy(warrior, enemy_dirs[0])   # don't evacuate if enemy can be captured
    else
      @bound_damage = damage_estimate(enemy_dirs.map{ |d| warrior.feel(d) })  # hack for early levels (no :listen!)
      @evacuation_dir = ALL_DIRS.find { |d| warrior.feel(d).empty? && !warrior.feel(d).stairs? } || :forward
      move(warrior, @evacuation_dir)
    end
  end

  def move(warrior, dir)
    @bound_dirs = []  # TODO floor map
    warrior.walk!(dir)
  end
end
