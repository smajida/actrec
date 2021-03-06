function groupTrajectory(videofile)

% clear all;
% close all;
% disp('ActionRecognition: Started');

if exist(videofile, 'file') == 0
    error('%s is not a valid file.', videofile);
end

file = extractShortFilename(videofile);             % remove extension

desc_file = [file, '.desc'];    % filename+.desc  Recommended, can change
raw_file = [file, '.raw'];  % filename+.raw  DO NOT change
draw_rst = 0;

%% Generate dense trajectory
fprintf('\n\nExtracting trajectories...\n');
command = ['./Actrec ', videofile, ' > ', desc_file];
system(command);

%% Construct the affinity matrix from trajectories
disp('Computing distances...');
trajs = single(importdata(desc_file, '\t'));
[num_traj, ~] = size(trajs);
traj_mean = trajs(:,2:3);
%traj_shape = trajs(:,8:37);
traj_frame = trajs(:,1);

% distance between trajectory shapes
distance_s = zeros(num_traj, num_traj,'single');
for k=1:15
    traj_comp = trajs(:,(7+2*k-1):(7+2*k));
    v_s = dot(traj_comp, traj_comp, 2);
    dist_comp = bsxfun(@plus,v_s,v_s');
    dist_comp = dist_comp - 2*(traj_comp*traj_comp');
    distance_s = distance_s + sqrt(dist_comp);
    clear dist_comp;
end
distance_s = real(distance_s);
distance_s = distance_s/15.0;
clear v_s; clear traj_comp; clear dist_comp;
clear trajs;

% distance of mean spatial coordinates 
v_m = dot(traj_mean, traj_mean, 2);
distance_m = bsxfun(@plus,v_m,v_m') - 2*(traj_mean*traj_mean');
distance_m = sqrt(distance_m);
distance_m = real(distance_m);
clear v_m; clear traj_mean;


% temporal distance must be less 
distance_t = bsxfun(@minus, traj_frame', traj_frame);
distance_t = abs(distance_t);
%distance_t = bsxfun(@lt, distance_t, 15);
distance_t(distance_t>=15) = Inf;
distance_t(distance_t<15) = 1;


% integrated distances
dist = distance_m .* distance_s .* distance_t;
clear distance_m; clear distance_s; clear distance_t;
dist(isnan(dist)) = Inf;

% affinity
affinity = exp(-dist.*dist);
%dlmwrite('affinity.txt', affinity, 'delimiter', '\t', 'precision', 4);
clear distance; clear dist;

% number of clusters from scree test
K = getK(affinity);

%% convert the affinity matrix to the format needed for ganc
% This may be not needed when not considering the time constraint
affinity2 = double(triu(affinity));
sparse_aff = sparse(affinity2);
clear affinity; clear affinity2;

[R,C,V] = find(sparse_aff);
graph = [R,C,V];

graph_file = [file, '.wpairs'];
dlmwrite(graph_file, graph, 'delimiter', '\t');
clear affinity2; clear sparse_aff; clear graph; 
clear R; clear C; clear V;


%% run ganc to get clusters
command = ['./ganc -f ', graph_file, ' --one-based --float-weight'];
system(command);

clusters_k = K;%10;
command = ['./ganc -f ', graph_file, ' --one-based --float-weight', ' -c ', num2str(num_traj-clusters_k)];
system(command);


%% convert groups from 0-separated to cell matrix
group_file = [file, '.groups'];
fid = fopen(group_file);

 % for each group, the first two number of (start, end) frames
groups = cell(1,clusters_k);

tline = fgets(fid);
n = 0;
while (tline ~= -1)
    tline = str2double(tline);
    if tline == 0
        n = n + 1;
        groups{n} = [];
        groups{n} = [Inf, -Inf];
    else
        groups{n} = [groups{n},tline];
        frameno = traj_frame(tline);
        if (frameno<groups{n}(1))
            groups{n}(1) = frameno;
        end
        if (frameno>groups{n}(2))
            groups{n}(2) = frameno;
        end
    end
    
    tline = fgets(fid);
end

save([file,'.cellgroups'], 'groups');  % when load, it's a struct
disp('groups saved to cellgroups');

%% draw trajectories according to the groups
if (draw_rst)
    nGroup = size(groups,2);
    raw_trajs = single(importdata(raw_file));

    colors = cellstr(['k','r','b','g','c', 'w','m']');

    background = imread('background.jpg');
    imshow(background);
    hold on;

    for k=1:nGroup
        grp_k = groups{k};
        nTraj = size(grp_k, 2);
        for i=1:nTraj
               x = raw_trajs(grp_k(i), 1:2:30);
               y = raw_trajs(grp_k(i), 2:2:30);
               plot(x,y,'-', 'Color', colors{mod(k-1,7)+1});
               %plot(x(1),y(1),'o');
               %plot(x(15),y(15),'>');
        end
    end
    hold off;
end

clear raw_trajs; clear traj_mean;

%% substitute the previous two steps with refine group file if the ganc works
% cluster_file = [file, '.groups2'];
% clusters = importdata(cluster_file, '\t');
% [num_traj, ~] = size(clusters);
% 
% raw_trajs = importdata(raw_file);
% 
% colors = cellstr(['k','r','b','g','c', 'w','m']');
% 
% background = imread('background.jpg');
% imshow(background);
% hold on;
% 
% for k=1:1195 %num_traj
%     x = raw_trajs(k, 1:2:30);
%     y = raw_trajs(k, 2:2:30);
%     plot(x,y,'-', 'Color', colors{mod(clusters(k,2)-1,7)+1});
%     %plot(x(1),y(1),'o');
%     %plot(x(15),y(15),'>');
% end
% hold off;
end