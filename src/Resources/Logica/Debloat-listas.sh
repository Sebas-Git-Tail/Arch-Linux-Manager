# Se incluye con source desde Logica/Android.sh: las listas de apps de fábrica que quita
# el debloat (vienen de Debloat-Clave.sh, versión 5). Son solo datos.
# Tres niveles (recommended = Básico, advanced = Intermedio, expert = Extremo); cada nivel
# tiene listas por marca (_xiaomi, _motorola) y una común a todas las marcas.
# Cada nivel desinstala solo sus propias listas (Intermedio no incluye las de Básico).

#Recomendados

# Cada nivel tiene listas por marca (_xiaomi, _motorola) y una común a todas
declare -a recommended_xiaomi=(com.miui.analytics \
com.xiaomi.xmsfkeeper \
com.miui.misightservice \
com.miui.daemon \
com.miui.backup \
com.mi.healthglobal \
com.xiaomi.simactivate.service \
com.xiaomi.mtb \
com.xiaomi.mirror \
com.miui.tsmclient \
com.miui.miservice \
com.miui.cloudservice \
com.xiaomi.aiasst.vision \
com.miui.extraphoto \
com.miui.touchassistant \
com.mi.globalminusscreen \
com.xiaomi.barrage \
com.mi.appfinder \
com.xiaomi.cameratools \
com.xiaomi.glgm \
com.miui.cit \
com.android.inputsettings.overlay.miui \
com.miui.thirdappassistant \
com.miui.msa.global \
com.xiaomi.trustservice \
com.miui.micloudsync \
com.miui.videoplayer \
com.miui.accessibility \
com.xiaomi.payment \
com.miui.vsimcore \
com.miui.cleaner \
com.xiaomi.simactivate.service \
com.xiaomi.mtb \
com.miui.phrase \
com.miui.phone.carriers.overlay.h3g \
com.miui.phone.carriers.overlay.vodafone \
com.miui.qr \
com.miui.settings.rro.device.hide.statusbar.overlay \
com.miui.settings.rro.device.type.overlay \
com.xiaomi.mi_connect_service \
com.xiaomi.mipicks \
com.payjoy.access \
com.miui.yellowpage \
com.miui.player \
com.miuix.editor \
com.xiaomi.bluetooth \
com.miui.bugreport \
com.xiaomi.touchservice \
com.miui.cloudbackup \
com.android.systemui.overlay.miui \
android.autoinstalls.config.Xiaomi.model \
com.xiaomi.aon)

declare -a recommended_motorola=(com.motorola.nfwlocationattribution \
com.motorola.ccc.devicemanagement \
com.motorola.brapps \
com.indus.appstore \
com.glance.lockscreenM \
com.motorola.account \
com.motorola.smartfeed \
com.motorola.iotservice \
com.motorola.genie \
com.motorola.contacts.preloadcontacts \
com.motorola.android.coresettingsext.overlay.doubletap \
com.motorola.android.overlay.crystaltalkai \
com.motorola.android.providers.chromehomepage \
com.motorola.bug2go \
com.motorola.callredirectionservice \
com.motorola.contacts.preloadcontacts.overlay.vzw \
com.motorola.overlay.launcher3 \
com.motorola.safetycenter.resources.overlay \
com.motorola.setup.overlay.pai \
com.motorola.systemserver \
com.motorola.wifi.motowifimetrics \
com.motorola.help \
com.motorola.spectrum.setup.extensions \
com.motorola.motocit \
com.motorola.appforecast \
com.motorola.systemui.desk \
com.motorola.motocare \
android.autoinstalls.config.motorola.layout \
com.motorola.enterprise.adapter.service \
com.motorola.att.phone.extensions \
com.motorola.spaces \
com.motorola.timeweatherwidget \
com.motorola.dynamicvolume \
com.motorola.android.systemui.overlay.vzw \
com.motorola.android.systemui.overlay.usc \
com.motorola.gesture \
com.motorola.motcameradesktop \
com.motorola.mobiledesktop \
com.motorola.slpc_sys \
com.motorola.revoker.services \
com.motorola.aiservices \
com.motorola.android.fmradio \
com.motorola.omadm.service \
com.taboola.mip \
com.motorola.paks.notification \
com.motorola.paks \
com.motorola.omadm.vzw \
com.motorola.ccc.notification \
com.motorola.android.nativedropboxagent \
com.motorola.appdirectedsmsproxy \
com.motorola.mobiledesktop.core \
com.motorola.enterprise.service \
com.motorola.securityhub \
com.motorola.help.extlog \
com.motorola.moto \
com.motorola.demo \
com.motorola.livewallpaper3 \
com.motorola.hiddenmenuapp \
com.motorola.gamemode \
com.motorola.lifetimedata \
com.motorola.attvowifi \
com.aura.oobe.motorola \
com.motorola.dciservice \
com.motorola.bach.modemstats \
com.motorola.android.systemui.overlay.sprint \
com.motorola.android.systemui.overlay.tmo \
com.motorola.easyprefix)

declare -a recommended=(com.google.android.accessibility.switchaccess \
com.dti.telefonica \
com.google.ar.core \
com.android.theme.font.Exo2Regular \
com.google.android.apps.setupwizard.searchselector \
com.bluetooth.aptxmode \
com.inmobi.installer \
com.android.providers.settings.auto_generated_rro_product__ \
com.qualcomm.atfwd \
com.qualcomm.atfwd2 \
com.qualcomm.qti.remoteSimlockAuth \
com.qualcomm.qti.uim \
com.qualcomm.qti.uimGbaApp \
com.google.android.tag \
com.oem.euiccpartnerapp \
com.google.android.apps.nbu.files \
com.qualcomm.location \
com.amazon.appmanager \
com.android.theme.font.RookeryRegular \
com.qualcomm.qti.xrcb \
com.qualcomm.qti.xrvd.service \
com.google.android.calculator \
com.android.theme.icon.round \
com.android.theme.font.RobotoSlabRegular \
com.qti.qcc \
com.android.theme.icon.pebble \
com.motorola.vzw.pco.extensions.pcoreceiver \
com.google.android.apps.work.clouddpc \
com.google.android.calendar \
com.android.cellbroadcast.overlay \
com.android.cellbroadcastservice.overlay \
com.google.android.feedback \
com.google.android.apps.youtube.music \
com.google.android.youtube \
com.mediatek.ygps \
com.ironsource.appcloud.oobe.hutchison \
com.aura.oobe.vodafone \
de.telekom.tsc \
com.tencent.soter.soterserver \
com.google.ambient.streaming \
com.android.traceur \
com.android.egg \
com.google.android.apps.restore \
com.google.android.as \
com.mediatek.atmwifimeta \
com.android.managedprovisioning.overlay \
com.android.microdroid.empty_payload \
com.google.android.ondevicepersonalization.services \
com.android.providers.partnerbookmarks \
com.android.systemui.accessibility.accessibilitymenu \
com.google.android.federatedcompute \
com.google.android.as.oss \
com.google.android.adservices.api \
com.android.hotwordenrollment.okgoogle \
com.android.theme.font.notoserifsource \
com.mediatek.location.mtkgeofence \
com.facebook.services \
com.facebook.appmanager \
com.facebook.system \
com.google.android.apps.tachyon \
com.mediatek.mdmlsample \
com.mediatek.mdmconfig \
com.google.android.overlay.modules.healthfitness.forframework \
com.mediatek.gbaservice \
com.mediatek.voiceunlock \
com.microsoftsdk.crossdeviceservicebroker \
com.google.android.apps.maps \
com.google.mainline.adservices \
com.mediatek.lbs.em2.ui \
org.ifaa.aidl.manager \
com.google.android.gms.location.history \
com.android.hotwordenrollment.xgoogle \
com.google.android.videos \
com.google.android.onetimeinitializer \
com.google.android.apps.subscriptions.red \
com.goodix.fingerprint.setting \
com.google.android.gm \
com.bsp.catchlog \
com.google.android.apps.bard \
com.google.android.apps.photos \
com.microsoft.appmanager \
com.mediatek.engineermode \
com.google.android.apps.docs \
com.microsoft.deviceintegrationservice \
com.debug.loggerui \
com.google.android.gms.supervision \
com.wdstechnology.android.kryten \
com.mediatek.voicecommand)

#Avanzado

declare -a advanced_xiaomi=(com.mi.android.globalFileexplorer \
com.miui.misound \
com.android.camera \
com.xiaomi.cameramind \
com.miui.gallery \
com.miui.audiomonitor \
com.milink.service \
com.miui.euicc \
com.xiaomi.aicr \
com.xiaomi.aiservice \
com.miui.mediaviewer \
com.miui.mishare.connectivity \
com.xiaomi.account \
com.android.thememanager)

declare -a advanced_motorola=(com.motorola.personalize \
com.motorola.securityhubext \
com.motorola.om \
com.motorola.motolights \
com.motorola.installer \
com.motorola.audiorecorder \
com.motorola.dolby.dolbyui \
com.motorola.mykey)

declare -a advanced=(com.android.storagemanager \
com.google.android.projection.gearhead \
com.google.android.apps.wellbeing \
com.google.android.setupwizard \
com.google.android.contacts \
com.google.android.inputmethod.latin \
com.google.android.googlequicksearchbox \
com.google.android.healthconnect.controller \
com.mediatek.miravision.ui \
com.google.android.tts \
com.google.android.apps.safetyhub \
com.android.wallpaper.livepicker \
com.google.android.dialer \
com.google.android.apps.messaging \
com.android.chrome \
com.google.android.deskclock \
com.android.devicediagnostics \
com.google.android.inputmethod.latin \
com.android.providers.downloads.ui)

#Experto

declare -a expert_xiaomi=(com.xiaomi.discover \
com.miui.powerkeeper \
com.miui.securityadd \
com.xiaomi.finddevice \
com.xiaomi.xmsf \
com.miui.global.packageinstaller \
com.miui.notification \
com.miui.securitycore \
com.miui.securitycenter)

declare -a expert_motorola=(com.motorola.freeform)

declare -a expert=(com.android.vending \
com.google.android.cellbroadcastreceiver \
com.google.android.cellbroadcastservice \
com.android.location.fused)


