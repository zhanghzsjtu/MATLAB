function Lambda = det_classic_amf(z, Rhat_train, v)
%det_classic_amf 经典 AMF（单距离门）

invR = inv(Rhat_train);
Lambda = abs(v' * invR * z)^2 / real(v' * invR * v);
end
