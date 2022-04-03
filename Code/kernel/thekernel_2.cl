/// @file

__kernel void thekernel(__global float4*    color,                              // Color.
                        __global float4*    position,                           // Position.
                        __global float4*    velocity,                           // Velocity.
                        __global float4*    acceleration,                       // Acceleration.
                        __global float4*    position_int,                       // Position (intermediate).
                        __global float4*    velocity_int,                       // Velocity (intermediate).
                        __global float*     resting,                            // Resting distance.
                        __global int*       central,                            // Node.
                        __global int*       nearest,                            // Neighbour.
                        __global int*       offset,                             // Offset.
                        __global float*     parameter)                          // Parameter array.
{
  ////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////// INDEXES ///////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////
  unsigned int i = get_global_id(0);                                            // Global index [#].
  unsigned int j = 0;                                                           // Neighbour stride index.
  unsigned int j_min = 0;                                                       // Neighbour stride minimun index.
  unsigned int j_max = offset[i];                                               // Neighbour stride maximum index.
  unsigned int k = 0;                                                           // Neighbour tuple index.
  unsigned int n = central[j_max - 1];                                          // Node index.

  ////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////// CELL VARIABLES //////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////
  float4        c;                                                              // Central node color.
  float4        v                 = velocity[n];                                // Central node velocity.
  float4        a                 = acceleration[n];                            // Central node acceleration.
  float4        p_int             = position_int[n];                            // Central node position (intermediate).
  float4        v_int             = velocity_int[n];                            // Central node velocity (intermediate).
  float4        p_new             = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node position (new).
  float4        v_new             = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node velocity (new).
  float4        a_new             = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node acceleration (new).
  float4        v_est             = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node velocity (estimation).
  float4        a_est             = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node acceleration (estimation).
  float         g                 = parameter[0];                               // Central node gravity field.
  float         m                 = parameter[1];                               // Central node mass.
  float         K                 = parameter[2];                               // Neighbour link stiffness.
  float         B                 = parameter[3];                               // Central node friction.
  float         dt                = parameter[4];                               // Simulation time step [s].
  float4        Fe                = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node elastic force.  
  float4        Fv                = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node viscous force.
  float4        Fv_est            = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node viscous force (estimation).
  float4        Fg                = (float4)(0.0f, 0.0f, -m*g, 1.0f);           // Central node gravitational force. 
  float4        F                 = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node total force.
  float4        F_new             = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Central node total force (new).
  float4        neighbour         = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Neighbour node position.
  float4        link              = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Neighbour link.
  float4        D                 = (float4)(0.0f, 0.0f, 0.0f, 1.0f);           // Neighbour displacement.
  float         R                 = 0.0f;                                       // Neighbour link resting length.
  float         S                 = 0.0f;                                       // Neighbour link strain.
  float         L                 = 0.0f;                                       // Neighbour link length.

  // COMPUTING STRIDE MINIMUM INDEX:
  if (i == 0)
  {
    j_min = 0;                                                                  // Setting stride minimum (first stride)...
  }
  else
  {
    j_min = offset[i - 1];                                                      // Setting stride minimum (all others)...
  }

  // COMPUTING ELASTIC FORCE:
  for (j = j_min; j < j_max; j++)
  {
    k = nearest[j];                                                             // Computing neighbour index...
    neighbour = position_int[k];                                                // Getting neighbour position...
    link = neighbour - p_int;                                                   // Getting neighbour link vector...
    R = resting[j];                                                             // Getting neighbour link resting length...
    L = length(link);                                                           // Computing neighbour link length...
    S = L - R;                                                                  // Computing neighbour link strain...
    D = S*normalize(link);                                                      // Computing neighbour link displacement...
    Fe += K*D;                                                                  // Building up elastic force on central node...

    if (color[j].w != 0.1f)
    {
      color[j].xyz = colormap(0.7f*(1.0f + S/R));                               // Setting color...
    }
    
    if(L > 0.0f)
    {
      D = S*normalize(link);                                                    // Computing neighbour link displacement...
    }
    else
    {
      D = (float4)(0.0f, 0.0f, 0.0f, 0.0f);
    }

  }

  // COMPUTING TOTAL FORCE:
  Fv = -B*v_int;                                                                // Computing node viscous force...
  F = Fg + Fe + Fv;                                                             // Computing total node force...

  // COMPUTING NEW ACCELERATION ESTIMATION:
  a_est  = F/m;                                                                 // Computing acceleration...

  // COMPUTING NEW VELOCITY ESTIMATION:
  v_est = v + 0.5f*(a + a_est)*dt;                                              // Computing velocity...

  // COMPUTING NEW VISCOUS FORCE ESTIMATION:
  Fv_est = -B*v_est;                                                            // Computing node viscous force...

  // COMPUTING NEW TOTAL FORCE:
  F_new = Fg + Fe + Fv_est;                                                     // Computing total node force...

  // COMPUTING NEW ACCELERATION:
  a_new = F_new/m;                                                              // Computing acceleration...

  // COMPUTING NEW VELOCITY:
  v_new = v + 0.5f*(a + a_new)*dt;                                              // Computing velocity...

  // FIXING PROJECTIVE SPACE:
  v_new.w = 1.0f;                                                               // Adjusting projective space...
  a_new.w = 1.0f;                                                               // Adjusting projective space...

  // APPLYING GROUND CONSTRAINTS:
  if (p_int.z <= 0.0f)
  {
    p_int.z = -p_int.z;
    v_new.z = -v_new.z;
    a_new.z = -a_new.z;
  }

  // UPDATING KINEMATICS:
  position[n] = p_int;                                                          // Updating position [m]...
  velocity[n] = v_new;                                                          // Updating velocity [m/s]...
  acceleration[n] = a_new;                                                      // Updating acceleration [m/s^2]...
}
