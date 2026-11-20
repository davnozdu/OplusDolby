import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.UUID;

/**
 * Drives the Oplus "audiox" (Dolby) effect that lives on the global output mix, using exactly
 * the protocol the vendor's own com.oplus.audio.effectcenter uses: same UUID as effect type and
 * as effect uuid, priority 1 (asks for control), same parameter keys, same payload layout.
 *
 * The vendor settings app that would normally send these parameters is disabled on this SKU,
 * and the settings keys alone change nothing audible, so this is the only way to actually move
 * the effect. Runs under app_process as root - no app, no permissions, nothing to install.
 *
 *   info                      attach and print id / control / enabled
 *   on | off                  AudioEffect.setEnabled - the real master switch
 *   eq on | off               EQ_ENABLE   0x100100c9
 *   eqset <volIdx> <d0..d9>   EQ_GAINS    0x100100bc, payload {volIdx, 10, 10 x int(dB*2^22)}
 *   profile <0..14>           PROFILE     0x100100bb
 *   volidx <0..100>           VOLUME_IDX  0x100100be
 *   atten <dB>                ATTEN_DB    0x100100c2 (float bits payload)
 *   enhance on | off          SOUNDX      0x100100c5
 *   raw <key> <hex>           send an arbitrary parameter
 */
public class OplusAudiox {

    static final UUID UUID_AUDIOX = UUID.fromString("41f6c0f4-5d8f-11ec-bf63-0242ac130002");

    static final int KEY_PROFILE    = 0x100100bb;
    static final int KEY_EQ_GAINS   = 0x100100bc;
    static final int KEY_VOLUME_IDX = 0x100100be;
    static final int KEY_ATTEN_DB   = 0x100100c2;
    static final int KEY_SOUNDX     = 0x100100c5;
    static final int KEY_ATTEN_ALL  = 0x100100c8;
    static final int KEY_EQ_ENABLE  = 0x100100c9;

    /** the vendor app scales dB by 2^22 before handing the bands over */
    static final double Q22 = 4194304.0;

    static Object effect;
    static Method mSet, mRel, mHasControl, mGetEnabled, mGetId, mSetEnabled;

    static void attach() throws Exception {
        Class<?> cls = Class.forName("android.media.audiofx.AudioEffect");
        Constructor<?> c = cls.getConstructor(UUID.class, UUID.class, int.class, int.class);
        effect = c.newInstance(UUID_AUDIOX, UUID_AUDIOX, 1, 0);
        mSet = cls.getMethod("setParameter", int.class, byte[].class);
        mSetEnabled = cls.getMethod("setEnabled", boolean.class);
        mRel = cls.getMethod("release");
        mHasControl = cls.getMethod("hasControl");
        mGetEnabled = cls.getMethod("getEnabled");
        mGetId = cls.getMethod("getId");
        System.out.println("attached id=" + mGetId.invoke(effect) + " control=" + mHasControl.invoke(effect)
                + " enabled=" + mGetEnabled.invoke(effect));
    }

    static byte[] ints(int... v) {
        byte[] b = new byte[v.length * 4];
        for (int i = 0; i < v.length; i++) {
            b[i * 4] = (byte) (v[i] & 0xff);
            b[i * 4 + 1] = (byte) ((v[i] >>> 8) & 0xff);
            b[i * 4 + 2] = (byte) ((v[i] >>> 16) & 0xff);
            b[i * 4 + 3] = (byte) ((v[i] >>> 24) & 0xff);
        }
        return b;
    }

    static byte[] floats(float... v) {
        int[] asInts = new int[v.length];
        for (int i = 0; i < v.length; i++) asInts[i] = Float.floatToIntBits(v[i]);
        return ints(asInts);
    }

    static byte[] hex(String s) {
        s = s.replace(",", "").replace(" ", "").replace("0x", "");
        byte[] b = new byte[s.length() / 2];
        for (int i = 0; i < b.length; i++) b[i] = (byte) Integer.parseInt(s.substring(i * 2, i * 2 + 2), 16);
        return b;
    }

    static void send(int key, byte[] payload) throws Exception {
        int r = (Integer) mSet.invoke(effect, key, payload);
        System.out.println("key=0x" + Integer.toHexString(key) + " len=" + payload.length + " -> " + r);
    }

    static boolean flag(String s) {
        return s.equals("on") || s.equals("1") || s.equals("true");
    }

    public static void main(String[] a) throws Exception {
        attach();
        String cmd = a.length > 0 ? a[0] : "info";

        if (cmd.equals("on") || cmd.equals("off")) {
            int r = (Integer) mSetEnabled.invoke(effect, cmd.equals("on"));
            System.out.println("setEnabled(" + cmd + ") -> " + r + " enabled=" + mGetEnabled.invoke(effect));
        } else if (cmd.equals("eq")) {
            send(KEY_EQ_ENABLE, ints(flag(a[1]) ? 1 : 0));
        } else if (cmd.equals("eqset")) {
            int vol = Integer.parseInt(a[1]);
            int[] payload = new int[12];
            payload[0] = vol;
            payload[1] = 10;
            for (int i = 0; i < 10; i++) {
                double db = Double.parseDouble(a[i + 2]);
                payload[i + 2] = (int) Math.floor(db * Q22);
            }
            send(KEY_EQ_GAINS, ints(payload));
        } else if (cmd.equals("profile")) {
            send(KEY_PROFILE, ints(Integer.parseInt(a[1])));
        } else if (cmd.equals("volidx")) {
            send(KEY_VOLUME_IDX, ints(Integer.parseInt(a[1])));
        } else if (cmd.equals("atten")) {
            send(KEY_ATTEN_DB, floats(Float.parseFloat(a[1])));
        } else if (cmd.equals("enhance")) {
            send(KEY_SOUNDX, ints(flag(a[1]) ? 1 : 0));
        } else if (cmd.equals("raw")) {
            send((int) Long.parseLong(a[1].replace("0x", ""), 16), hex(a[2]));
        }

        if (effect != null) mRel.invoke(effect);
    }
}
