library(pacman)
p_load(tidyverse)
p_load(magrittr)
p_load(cowplot)


make_names <- function(names) {
  # Function to clean up column names
  names %>%
    stringr::str_trim() %>%
    stringr::str_replace("%","percent") %>%
    tolower() %>%
    make.names(unique = TRUE) %>%
    stringr::str_replace_all('[.]', '_') %>%
    stringr::str_replace_all('__{1,4}', '_') %>%
    stringr::str_replace_all('_$', '') %>%
    return
}

file1 <- read_csv('data/2021-02-17_11_20_32_my_iOS_device.csv')
file2 <- read_csv('data/2021-02-17_10_32_41_my_iOS_device.csv')
file3 <- read_csv('data/2021-02-17_10_52_46_my_iOS_device.csv')

clean_up <- function(df) {
  names(df) %<>% make_names

  f = rep(.25,4)

  df %<>%
    mutate(
      motion_ts_min = (motiontimestamp_sincereboot_s - min(motiontimestamp_sincereboot_s))/60,
      altimeter_ts_min = (altimetertimestamp_sincereboot_s - min(altimetertimestamp_sincereboot_s))/60,
      magnetometer_ts_min = (magnetometertimestamp_sincereboot_s - min(magnetometertimestamp_sincereboot_s))/60,
      accelerometer_ts_min = (accelerometertimestamp_sincereboot_s - min(accelerometertimestamp_sincereboot_s))/60,

      user_total_accel = sqrt(motionuseraccelerationx_g^2+motionuseraccelerationy_g^2+motionuseraccelerationz_g^2),
      user_smoothed_accel = stats::filter(user_total_accel, f, sides = 2),
      total_accel = sqrt(accelerometeraccelerationx_g^2+accelerometeraccelerationy_g^2+accelerometeraccelerationz_g^2),
      smoothed_accel = stats::filter(total_accel, f, sides = 2)
    ) %>%
    filter(complete.cases(smoothed_accel))

  accel_spline <- smooth.spline(df$accelerometer_ts_min, y=df$smoothed_accel, df = 1000)

  df = cbind(df, accel_spline = accel_spline$y)

}

file1 %<>% clean_up
file2 %<>% clean_up
file3 %<>% clean_up

file2


plot_4 <- function(df){

  p1.1 <- ggplot(df, aes(x=altimeter_ts_min)) +
    geom_line(aes(y=altimeterrelativealtitude_m), col = 'red', alpha = .5) +
    xlab("") +
    theme_minimal()


  # p1.2 <- ggplot(file1, aes(x=motion_ts_min)) +
  #   geom_line(aes(y=motionuseraccelerationx_g), col = 'red', alpha = .5) +
  #   geom_line(aes(y=motionuseraccelerationy_g), col = 'blue', alpha = .5) +
  #   geom_line(aes(y=motionuseraccelerationz_g), col = 'green', alpha = .5) +
  #   xlab("") +
  #   theme_minimal()


  p1.2 <- ggplot(df, aes(x=motion_ts_min)) +
    # geom_line(aes(y=total_accel), col = 'red', alpha = .5) +
    geom_line(aes(y=smoothed_accel), col = 'blue', alpha = .5) +
    # geom_line(aes(y=motionuseraccelerationz_g), col = 'green', alpha = .5) +
    xlab("") +
    theme_minimal()


  p1.3 <- ggplot(df, aes(x=motion_ts_min)) +
    # geom_line(aes(y=total_accel), col = 'red', alpha = .5) +
    geom_line(aes(y=accel_spline), col = 'blue', alpha = .5) +
    # geom_line(aes(y=motionuseraccelerationz_g), col = 'green', alpha = .5) +
    xlab("") +
    theme_minimal()


  p1.4 <- ggplot(df, aes(x=magnetometer_ts_min)) +
    geom_line(aes(y=magnetometerx_µt), col = 'red', alpha = .5) +
    geom_line(aes(y=magnetometery_µt), col = 'blue', alpha = .5) +
    geom_line(aes(y=magnetometerz_µt), col = 'green', alpha = .5) +
    xlab("") +
    theme_minimal()

  plot_grid(p1.1, p1.2, p1.3, p1.4,
            ncol = 1, nrow = 4)
}

plot_4(file1)


ggplot(file2, aes(x=altimetertimestamp_sincereboot_s)) +
  geom_line(aes(y=altimeterrelativealtitude_m), col = 'red', alpha = .5) +
  theme_minimal()


loc_df <- file1 %>%
  select(starts_with('location')) %>%
  select(!contains('heading')) %>%
  distinct
