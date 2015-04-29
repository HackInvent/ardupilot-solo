/// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: nil -*-

/*
 * control_sport.pde - init and run calls for sport flight mode
 */

// sport_init - initialise sport controller
static bool sport_init(bool ignore_checks)
{
    // initialize vertical speed and accelerationj
    pos_control.set_speed_z(-g.pilot_velocity_z_max, g.pilot_velocity_z_max);
    pos_control.set_accel_z(g.pilot_accel_z);

    // initialise altitude target to stopping point
    pos_control.set_target_to_stopping_point_z_ff();

    return true;
}

// sport_run - runs the sport controller
// should be called at 100hz or more
static void sport_run()
{
    float target_roll_rate, target_pitch_rate, target_yaw_rate;
    float target_climb_rate = 0;

    // if not armed or throttle at zero, set throttle to zero and exit immediately
    if(!motors.armed() || g.rc_3.control_in <= 0) {
        attitude_control.set_throttle_out_unstabilized(0,true,g.throttle_filt);
        pos_control.relax_alt_hold_controllers(get_throttle_pre_takeoff(g.rc_3.control_in)-throttle_average);
        return;
    }

    // apply SIMPLE mode transform
    update_simple_mode();

    // get pilot's desired roll and pitch rates

    // calculate rate requests
    target_roll_rate = g.rc_1.control_in * g.acro_rp_p;
    target_pitch_rate = g.rc_2.control_in * g.acro_rp_p;

    int32_t roll_angle = wrap_180_cd(ahrs.roll_sensor);
    target_roll_rate -= constrain_int32(roll_angle, -ACRO_LEVEL_MAX_ANGLE, ACRO_LEVEL_MAX_ANGLE) * g.acro_balance_roll;

    // Calculate trainer mode earth frame rate command for pitch
    int32_t pitch_angle = wrap_180_cd(ahrs.pitch_sensor);
    target_pitch_rate -= constrain_int32(pitch_angle, -ACRO_LEVEL_MAX_ANGLE, ACRO_LEVEL_MAX_ANGLE) * g.acro_balance_pitch;

    if (roll_angle > aparm.angle_max){
        target_roll_rate -=  g.acro_rp_p*(roll_angle-aparm.angle_max);
    }else if (roll_angle < -aparm.angle_max) {
        target_roll_rate -=  g.acro_rp_p*(roll_angle+aparm.angle_max);
    }

    if (pitch_angle > aparm.angle_max){
        target_pitch_rate -=  g.acro_rp_p*(pitch_angle-aparm.angle_max);
    }else if (pitch_angle < -aparm.angle_max) {
        target_pitch_rate -=  g.acro_rp_p*(pitch_angle+aparm.angle_max);
    }

    // get pilot's desired yaw rate
    target_yaw_rate = get_pilot_desired_yaw_rate(g.rc_4.control_in);

    // get pilot desired climb rate
    target_climb_rate = get_pilot_desired_climb_rate(g.rc_3.control_in);
    target_climb_rate = constrain_float(target_climb_rate, -g.pilot_velocity_z_max-tkoff_get_speed(), g.pilot_velocity_z_max-tkoff_get_speed());

    // check for take-off
    if (ap.land_complete && (takeoff_state.running || g.rc_3.control_in > get_takeoff_trigger_throttle())) {
        if (!takeoff_state.running) {
            tkoff_timer_start(constrain_float(g.pilot_takeoff_alt,0.0f,1000.0f));
        }

        // indicate we are taking off
        set_land_complete(false);
        // clear i term when we're taking off
        set_throttle_takeoff();
    }

    // reset target lean angles and heading while landed
    if (ap.land_complete) {
        // move throttle to between minimum and non-takeoff-throttle to keep us on the ground
        attitude_control.set_throttle_out_unstabilized(get_throttle_pre_takeoff(g.rc_3.control_in),true,g.throttle_filt);
        pos_control.relax_alt_hold_controllers(get_throttle_pre_takeoff(g.rc_3.control_in)-throttle_average);
    }else{

        // call attitude controller
        attitude_control.rate_ef_roll_pitch_yaw(target_roll_rate, target_pitch_rate, target_yaw_rate);

        // call throttle controller
        if (sonar_alt_health >= SONAR_ALT_HEALTH_MAX) {
            // if sonar is ok, use surface tracking
            target_climb_rate = get_surface_tracking_climb_rate(target_climb_rate, pos_control.get_alt_target(), G_Dt);
        }

        // call position controller
        pos_control.set_alt_target_from_climb_rate_ff(target_climb_rate, G_Dt);
        tkoff_increment_alt_target(G_Dt);
        pos_control.update_z_controller();
    }
}
