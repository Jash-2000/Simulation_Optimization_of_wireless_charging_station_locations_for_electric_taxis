# Additional instructions for executing the animation script.

**Please note that our script is, by defualt, developed for running the simulation only. Hence, if you skip any of the following steps or directly press "enter" in the previous step described in [readme.me](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/Readme.md), you might end up watching only the simulation.**

   * **Step 1** - In the prompt that you see, type **"Yes" or "Y" or "y" or "yes"** and press enter. Wait for some time and you would be able to see that the julia REPL has finished exectution, but you wont be able to type any other commands. This marks the successful Client-Server communication link between Julia REPL and Javascript Server. The following image descibes this stage visually.

![Step_1_image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/Julia_JS.png)
[Link to image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/Julia_JS.png)

   * **Step 2** - After some time, your default browser will automatically open at port 8001. As soon as you see the map getting loaded up, press **"F12" or "Fn+F12" or "Cntr + Shift + I" i.e. "Inspect elements"**. It will take some time in loading the map and once loaded and depending upon the computing power of the device, may come loaded with the ranks, it will look like the following image.

![Step_2_image_1](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/first_screen.PNG)
[Link to image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/first_screen.PNG)

   Wait for all the ranks to be initialized 

![Step_2_image_2](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/second_screen.PNG)
[Link to image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/second_screen.PNG)

   * **Step 3** - Zoom in to the area of interest on the map. After all the ranks get loaded onto the map, you would be able to see **"Press_the_run_button!!!!!!"** in the console. Pressing this will initiate the actual process. Do not worry if the same message gets displayed several times as it won't stop untill you press the **run** button. For example in the following image, it was displayed for 741 times. 

![Step_3_image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/Run_Pause.PNG)
[Link to image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/Run_Pause.PNG)

   * **Step 4** - AFter this, you would be clearly able to see when the ranks get refreshed (they will disappear for a split second). This means that the process was set up successfully. You can now view the map in full screen by closing the console window. The map would look like this 

![Step_4_image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/running.PNG)
[Link to image](https://bitbucket.org/araith/evrouting/src/master/wireless_charging/images/running.PNG)