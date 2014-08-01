# Clippyboard

This is my project for Flipboard's inaugural hackathon 8/1/14.

It was inspired by [this Tweet](https://twitter.com/naveen/status/493890969360945152) by [@naveen](https://twitter.com/naveen), a [recent project](http://ryhan.org/post/91998722446/i-love-the-vision-behind-apples-handoff) done by a Dropbox designer, and a [recent hack project](http://youtu.be/zxF9jBcsQT4) done by one of our interns for the Greylock hack fest.

## The Idea

As a developer I've always got at least two devices running all the time, my phone and my Mac. I've constantly got long URLs, unwieldy JSON blobs, and screens shots I need to transfer between the two. I usually do this by copying then uploading to Dropbox or emailing myself.

My idea was **what if the two had the same clipboard?**

![](http://cl.ly/image/382V2n353d31/Screen%20Shot%202014-08-01%20at%205.25.08%20PM.png)

## Implementation

I wrote a Mac app and an iOS app, in the Clippy-Mac and Clippy-iOS directories respectively. These apps use the [Dropbox Sync API](https://www.dropbox.com/developers/sync) to transport pasteboard data whenever it changes on one device.

![](http://cl.ly/image/1z0l420m0s2S/phone.png)
![](http://cl.ly/image/3d2u33293836/mac.png)

Additionally, if you take a screenshot on your iPhone it's uploaded to the pasteboard of your Mac without you having to copy it.

![](http://cl.ly/image/191U2G301o3F/Screen%20Shot%202014-08-01%20at%205.33.02%20PM.png)

And if you copy a photo to the pasteboard on your Mac the phone app will offer to save it your camera roll since a photo on an iPhone pasteboard isn't especially useful.

![](http://cl.ly/image/3I1a003D2K34/save.png)

This is definitely a hack.

- I made the iOS app VoIP enabled to keep it alive in the background
- I poll the pasteboard on both platforms and copy its contents
- I poll the camera roll on iOS and copy its contents whenver it changes
- I save every pasteboard change as a file in Dropbox, not safe for sensitive content

So in its current state it definitely couldn't ship anytime soon. Given time to clean it up and make it viable I'd still love to release it. I used it in the process of writing these very release notes to get screenshots from my phone.

If you'd like to try it out you'll need to search both projects for `<DROPBOX-KEY>` and `<DROPBOX-SECRET>` and replace them with the keys for a Dropbox app you create yourself.